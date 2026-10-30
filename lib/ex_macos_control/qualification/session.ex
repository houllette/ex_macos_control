defmodule ExMacOSControl.Qualification.Session do
  @moduledoc false
  alias ExMacOSControl.{Automation, Error}
  alias ExMacOSControl.Qualification.{Journal, Manifest}

  def new(manifest, profile, backend, journal) do
    %{
      manifest: manifest,
      profile: profile,
      backend: backend,
      journal: journal,
      deadline: now() + manifest["limits"]["deadline_ms"],
      effects: 0,
      sends: 0,
      id: nil,
      halted: false,
      marker: "EXMC-QA-" <> journal.run_id
    }
  end

  def guard(state) do
    with {:ok, _} <- Manifest.validate(state.manifest, state.profile),
         true <- remaining(state) > 0,
         {:ok, _snapshot} <- state.backend.guard(state.manifest, state.profile, options(state)),
         true <- remaining(state) > 0 do
      :ok
    else
      _ -> Automation.invalid("Qualification authorization, identity, or deadline check failed")
    end
  rescue
    _ -> Automation.invalid("Qualification preflight raised; refusing effects")
  catch
    _, _ -> Automation.invalid("Qualification preflight exited; refusing effects")
  end

  def effect(state, operation) do
    with :ok <- allowed(state, operation),
         :ok <- guard(state),
         :ok <- Journal.append(state.journal, %{event: "intent", operation: operation, sequence: state.effects + 1}),
         {:ok, _} <- Manifest.validate(state.manifest, state.profile),
         true <- remaining(state) > 0 do
      state = %{state | effects: state.effects + 1, sends: state.sends + if(operation == :mail_send, do: 1, else: 0)}
      acknowledge(state, operation, invoke(state, :perform, operation))
    else
      _ -> failure(state, "Operation refused before dispatch")
    end
  end

  def observe(state, operation) do
    with :ok <- guard(state) do
      invoke(state, :observe, operation)
    end
  end

  def options(state), do: [timeout: max(remaining(state), 1), max_output_bytes: state.manifest["limits"]["max_bytes"]]
  def remaining(state), do: max(state.deadline - now(), 0)

  defp allowed(state, operation) do
    operations = if state.profile == "notes-crud", do: [:notes_create, :notes_update, :notes_delete], else: [:mail_send]

    valid_target = valid_target?(state, operation)

    limits = state.manifest["limits"]
    send_available = operation != :mail_send or state.sends < limits["max_sends"]

    if not state.halted and operation in operations and valid_target and state.effects < limits["max_effects"] and
         send_available,
       do: :ok,
       else: Automation.invalid("Operation is outside the profile or its effect/send budget")
  end

  defp valid_target?(state, :notes_create), do: is_nil(state.id)
  defp valid_target?(_state, :mail_send), do: true
  defp valid_target?(state, _), do: is_binary(state.id)

  defp invoke(state, method, operation) do
    context = %{marker: state.marker, id: state.id, deadline: state.deadline, expires_at: state.manifest["expires_at"]}
    apply(state.backend, method, [operation, state.manifest, context, options(state)])
  rescue
    _ -> Automation.invalid("Qualification backend raised; operation outcome is unknown")
  catch
    _, _ -> Automation.invalid("Qualification backend exited; operation outcome is unknown")
  end

  defp acknowledge(state, :notes_create, {:ok, id}) when is_binary(id) and byte_size(id) in 1..1024 do
    state = %{state | id: id}
    record_acknowledgement(state, :notes_create, %{object_id: id})
  end

  defp acknowledge(state, operation, :ok) when operation in [:notes_update, :notes_delete, :mail_send],
    do: record_acknowledgement(state, operation, %{})

  defp acknowledge(state, operation, _result) do
    Journal.append(state.journal, %{event: "unknown", operation: operation})
    failure(state, "Operation was not acknowledged; reconcile the journal before another run")
  end

  defp record_acknowledgement(state, operation, details) do
    case Journal.append(state.journal, Map.merge(details, %{event: "acknowledged", operation: operation})) do
      :ok -> {:ok, state}
      _ -> failure(state, "Unable to persist acknowledgement; reconcile before another run")
    end
  end

  defp failure(state, message), do: {:error, Error.execution_error(message), %{state | halted: true}}
  defp now, do: System.monotonic_time(:millisecond)
end
