defmodule ExMacOSControl.Qualification.Capture do
  @moduledoc false
  use GenServer
  alias ExMacOSControl.Automation

  def start(opts), do: GenServer.start(__MODULE__, {self(), opts})
  def messages(server), do: GenServer.call(server, :messages)
  def port(server), do: GenServer.call(server, :port)

  def stop(server) do
    GenServer.stop(server, :normal, 1000)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, {:normal, _} -> :ok
  end

  @impl true
  def init({owner, opts}) do
    case :gen_tcp.listen(opts[:port], [
           :binary,
           packet: :line,
           packet_size: 8192,
           active: false,
           ip: {127, 0, 0, 1},
           reuseaddr: false
         ]) do
      {:ok, listener} ->
        server = self()
        worker = spawn_link(fn -> accept(listener, server, opts) end)
        {:ok, %{listener: listener, worker: worker, owner: Process.monitor(owner), messages: [], opts: opts}}

      error ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:ok, {_ip, port}} = :inet.sockname(state.listener)
    {:reply, port, state}
  end

  def handle_call(:messages, _from, state), do: {:reply, Enum.reverse(state.messages), state}

  def handle_call({:capture, message}, _from, %{messages: []} = state),
    do: {:reply, :ok, %{state | messages: [message]}}

  def handle_call({:capture, _}, _from, state), do: {:reply, {:error, :send_limit}, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner: ref} = state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state) do
    :gen_tcp.close(state.listener)
    Process.unlink(state.worker)
    Process.exit(state.worker, :kill)
  end

  defp accept(listener, server, opts) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          :gen_tcp.send(socket, "220 exmc-capture\r\n")
          commands(socket, server, opts, %{from: nil, to: []}, 0)
        after
          :gen_tcp.close(socket)
        end

        accept(listener, server, opts)

      _ ->
        :ok
    end
  end

  defp commands(socket, server, opts, envelope, count) when count < 100 do
    with {:ok, line} <- :gen_tcp.recv(socket, 0, 1000) do
      {reply, next} = command(String.trim_trailing(line), socket, server, opts, envelope)
      :gen_tcp.send(socket, reply)
      if next != :quit, do: commands(socket, server, opts, next, count + 1)
    end
  end

  defp commands(_, _, _, _, _), do: :ok

  defp command(line, socket, server, opts, envelope) do
    case String.split(line, " ", parts: 2) do
      [verb | rest] -> dispatch(String.upcase(verb), Enum.join(rest, " "), socket, server, opts, envelope)
    end
  end

  defp dispatch("EHLO", _, _, _, opts, envelope),
    do: {"250-exmc-capture\r\n250 SIZE #{opts[:max_bytes]}\r\n", envelope}

  defp dispatch("HELO", _, _, _, _, envelope), do: {"250 exmc-capture\r\n", envelope}

  defp dispatch("QUIT", _, _, _, _, _), do: {"221 Bye\r\n", :quit}
  defp dispatch("NOOP", _, _, _, _, envelope), do: {"250 OK\r\n", envelope}
  defp dispatch("RSET", _, _, _, _, _), do: {"250 OK\r\n", %{from: nil, to: []}}

  defp dispatch("MAIL", value, _, _, opts, _envelope) do
    if Regex.match?(~r/\AFROM:<#{Regex.escape(opts[:sender])}>(?: SIZE=\d+)?\z/i, value),
      do: {"250 OK\r\n", %{from: opts[:sender], to: []}},
      else: {"550 Sender refused\r\n", %{from: nil, to: []}}
  end

  defp dispatch("RCPT", value, _, _, opts, envelope) do
    if envelope.from && envelope.to == [] && String.downcase(value) == "to:<#{opts[:recipient]}>",
      do: {"250 OK\r\n", %{envelope | to: [opts[:recipient]]}},
      else: {"550 Recipient refused\r\n", envelope}
  end

  defp dispatch("DATA", "", socket, server, opts, %{from: from, to: [_]} = envelope) when not is_nil(from) do
    :gen_tcp.send(socket, "354 End with dot\r\n")

    case data(socket, opts[:max_bytes], [], 0) do
      {:ok, bytes} ->
        message = Map.put(envelope, :data, bytes)

        if GenServer.call(server, {:capture, message}) == :ok,
          do: {"250 Captured\r\n", %{from: nil, to: []}},
          else: {"452 Send limit reached\r\n", :quit}

      _ ->
        {"552 Capture refused\r\n", :quit}
    end
  end

  defp dispatch(_, _, _, _, _, envelope), do: {"502 Unsupported\r\n", envelope}

  defp data(socket, maximum, chunks, size) do
    case :gen_tcp.recv(socket, 0, 1000) do
      {:ok, ".\r\n"} ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {:ok, line} when size + byte_size(line) <= maximum ->
        line = if String.starts_with?(line, ".."), do: binary_part(line, 1, byte_size(line) - 1), else: line
        data(socket, maximum, [line | chunks], size + byte_size(line))

      _ ->
        {:error, :capture_limit}
    end
  end

  def verify(server, sender, recipient, marker) do
    case messages(server) do
      [%{from: ^sender, to: [^recipient], data: bytes}] -> verify_data(bytes, marker)
      _ -> Automation.invalid("Expected exactly one captured message to the configured recipient")
    end
  end

  defp verify_data(bytes, marker) do
    case String.split(bytes, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        verify_plaintext(headers, body, bytes, marker)

      _ ->
        Automation.invalid("Captured message has no header/body boundary")
    end
  end

  defp verify_plaintext(headers, body, bytes, marker) do
    with {:ok, fields} <- header_fields(headers),
         ^marker <- fields["subject"],
         true <- Regex.match?(~r/\Atext\/plain(?:;|\z)/i, Map.get(fields, "content-type", "text/plain")),
         {:ok, decoded} <- decode_body(body, String.downcase(Map.get(fields, "content-transfer-encoding", "7bit"))),
         true <- String.trim(decoded) == marker do
      {:ok, Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)}
    else
      _ -> Automation.invalid("Captured message must contain exactly the expected plain-text subject and body")
    end
  end

  defp header_fields(headers) do
    unfolded = String.replace(headers, ~r/\r\n[ \t]+/, " ")

    Enum.reduce_while(String.split(unfolded, "\r\n"), {:ok, %{}}, fn line, {:ok, fields} ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> add_header(fields, String.downcase(key), String.trim(value))
        _ -> {:halt, {:error, :invalid_header}}
      end
    end)
  end

  defp add_header(fields, key, value) do
    if Map.has_key?(fields, key),
      do: {:halt, {:error, :duplicate_header}},
      else: {:cont, {:ok, Map.put(fields, key, value)}}
  end

  defp decode_body(body, encoding) when encoding in ["7bit", "8bit"], do: {:ok, body}
  defp decode_body(body, "base64"), do: Base.decode64(String.replace(body, ~r/\s/, ""))

  defp decode_body(body, "quoted-printable") do
    unfolded = String.replace(body, ~r/=\r?\n/, "")
    {:ok, Regex.replace(~r/=([0-9A-Fa-f]{2})/, unfolded, fn _, hex -> <<String.to_integer(hex, 16)>> end)}
  end

  defp decode_body(_, _), do: {:error, :unsupported_encoding}
end
