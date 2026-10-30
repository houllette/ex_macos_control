defmodule ExMacOSControl.Qualification.Suite do
  @moduledoc false
  alias ExMacOSControl.{Automation, Wait}
  alias ExMacOSControl.Qualification.{Capture, Journal, Session}

  def run(%{profile: "notes-crud"} = state) do
    steps = [
      effect: :notes_create,
      assert: :created,
      effect: :notes_update,
      assert: :updated,
      effect: :notes_delete,
      assert: :absent
    ]

    Enum.reduce_while(steps, {:ok, state}, fn step, {:ok, current} ->
      case step(current, step) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  def run(%{profile: "mail-capture"} = state) do
    case Session.observe(state, :mail_idle) do
      {:ok, true} -> capture_delivery(state)
      _ -> failed(state, "Mail must have an empty outgoing queue before opening capture")
    end
  end

  defp capture_delivery(state) do
    fixture = state.manifest["fixtures"]["mail"]

    options = [
      port: fixture["smtp_port"],
      sender: fixture["sender"],
      recipient: fixture["recipient"],
      max_bytes: state.manifest["limits"]["max_bytes"]
    ]

    case Capture.start(options) do
      {:ok, server} ->
        try do
          send_and_verify(state, server, fixture)
        after
          Capture.stop(server)
        end

      _ ->
        failed(state, "Loopback capture port unavailable; refusing to send")
    end
  end

  defp send_and_verify(state, server, fixture) do
    with {:ok, true} <- Session.observe(state, :mail_idle),
         {:ok, next} <- Session.effect(state, :mail_send) do
      verify_delivery(next, server, fixture)
    else
      {:error, _, _} = error -> error
      _ -> failed(state, "Mail must have an empty outgoing queue before capture")
    end
  end

  defp verify_delivery(state, server, fixture) do
    result = Wait.until(fn -> Capture.messages(server) != [] end, timeout: Session.remaining(state), interval: 20)

    with :ok <- result,
         {:ok, hash} <- Capture.verify(server, fixture["sender"], fixture["recipient"], state.marker),
         {:ok, true} <- Session.observe(state, :mail_idle),
         :ok <- Journal.append(state.journal, %{event: "captured", sha256: hash}) do
      {:ok, state}
    else
      _ -> failed(state, "Captured delivery or outgoing-queue verification failed; do not resend")
    end
  end

  defp step(state, {:effect, operation}), do: Session.effect(state, operation)

  defp step(state, {:assert, :absent}) do
    case Session.observe(state, :notes_absent) do
      {:ok, true} -> {:ok, state}
      _ -> failed(state, "Deleted note remains present or absence could not be verified")
    end
  end

  defp step(state, {:assert, stage}) do
    expected = state.marker <> if(stage == :updated, do: " changed", else: "")

    case Session.observe(state, :notes_get) do
      {:ok, %{title: title, plaintext: text, folder_id: folder}} when is_binary(text) ->
        matches =
          title == state.marker and String.trim(text) == expected and
            folder == state.manifest["fixtures"]["notes"]["folder_id"]

        if matches, do: {:ok, state}, else: failed(state, "Note read-back differs from the expected fixture")

      _ ->
        failed(state, "Note read-back failed")
    end
  end

  defp failed(state, message) do
    {:error, error} = Automation.invalid(message)
    {:error, error, state}
  end
end
