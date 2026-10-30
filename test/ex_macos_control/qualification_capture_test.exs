defmodule ExMacOSControl.Qualification.CaptureTest do
  use ExUnit.Case, async: false
  alias ExMacOSControl.{Error, QualificationFixture}
  alias ExMacOSControl.Qualification.{Capture, Runner}

  setup do
    {:ok, server} =
      Capture.start(port: 0, sender: "sender@qa.invalid", recipient: "sink@qa.invalid", max_bytes: 1024)

    on_exit(fn -> if Process.alive?(server), do: Capture.stop(server) end)
    %{server: server, port: Capture.port(server)}
  end

  test "captures one exact envelope and refuses a second DATA transaction", %{port: port, server: server} do
    socket = connect(port)
    assert line(socket, "MAIL FROM:<sender@qa.invalid>") =~ "250"
    assert line(socket, "RCPT TO:<sink@qa.invalid>") =~ "250"
    assert line(socket, "DATA") =~ "354"
    assert line(socket, "Subject: marker\r\n\r\nmarker\r\n.") =~ "250"
    assert {:ok, hash} = Capture.verify(server, "sender@qa.invalid", "sink@qa.invalid", "marker")
    assert byte_size(hash) == 64
    assert line(socket, "MAIL FROM:<sender@qa.invalid>") =~ "250"
    assert line(socket, "RCPT TO:<sink@qa.invalid>") =~ "250"
    assert line(socket, "DATA") =~ "354"
    assert line(socket, "Subject: marker\r\n\r\nmarker\r\n.") =~ "452"
    assert length(Capture.messages(server)) == 1
    :gen_tcp.close(socket)
  end

  test "rejects other senders, recipients, authentication and oversized content", %{port: port, server: server} do
    socket = connect(port)
    assert line(socket, "MAIL FROM:<personal@example.com>") =~ "550"
    assert line(socket, "RCPT TO:<sink@qa.invalid>") =~ "550"
    assert line(socket, "AUTH LOGIN") =~ "502"
    assert line(socket, "MAIL FROM:<sender@qa.invalid>") =~ "250"
    assert line(socket, "RCPT TO:<personal@example.com>") =~ "550"
    assert line(socket, "RCPT TO:<sink@qa.invalid>") =~ "250"
    assert line(socket, "RCPT TO:<sink@qa.invalid>") =~ "550"
    assert line(socket, "DATA") =~ "354"
    assert line(socket, String.duplicate("x", 1025)) =~ "552"
    assert Capture.messages(server) == []
    :gen_tcp.close(socket)
  end

  test "capture verification requires the matching content and no duplicate Subject header", %{
    port: port,
    server: server
  } do
    socket = connect(port)
    line(socket, "MAIL FROM:<sender@qa.invalid>")
    line(socket, "RCPT TO:<sink@qa.invalid>")
    line(socket, "DATA")
    line(socket, "Subject: marker\r\nSubject: other\r\n\r\nmarker\r\n.")
    assert {:error, %Error{}} = Capture.verify(server, "sender@qa.invalid", "sink@qa.invalid", "marker")
    :gen_tcp.close(socket)
  end

  for {encoding, content} <- [{"base64", Base.encode64("marker\r\n")}, {"quoted-printable", "mar=6Ber\r\n"}] do
    test "verifies the exact plain-text payload using #{encoding}", %{port: port, server: server} do
      socket = connect(port)
      line(socket, "MAIL FROM:<sender@qa.invalid>")
      line(socket, "RCPT TO:<sink@qa.invalid>")
      line(socket, "DATA")

      line(
        socket,
        "Subject: marker\r\nContent-Type: text/plain;\r\n charset=us-ascii\r\nContent-Transfer-Encoding: #{String.upcase(unquote(encoding))}\r\n\r\n#{String.trim_trailing(unquote(content))}\r\n."
      )

      assert {:ok, _} = Capture.verify(server, "sender@qa.invalid", "sink@qa.invalid", "marker")
      :gen_tcp.close(socket)
    end
  end

  test "an extra body paragraph cannot pass by including the marker", %{port: port, server: server} do
    socket = connect(port)
    line(socket, "MAIL FROM:<sender@qa.invalid>")
    line(socket, "RCPT TO:<sink@qa.invalid>")
    line(socket, "DATA")
    line(socket, "Subject: marker\r\n\r\nmarker\r\nunexpected extra content\r\n.")
    assert {:error, %Error{}} = Capture.verify(server, "sender@qa.invalid", "sink@qa.invalid", "marker")
    :gen_tcp.close(socket)
  end

  test "full capture profile uses the isolated SMTP receiver as its delivery oracle", %{port: port} do
    # Use another port so the runner must bind and own its own capture listener.
    # The fixture backend emits a synthetic SMTP transaction, never an app event.
    workspace = Path.expand("tmp/capture-run-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    manifest =
      QualificationFixture.manifest(workspace, "mail-capture")
      |> put_in(["fixtures", "mail", "smtp_port"], unused_port(port))

    QualificationFixture.setup(manifest)

    assert {:ok, %{status: "passed", sends: 1, effects: 1}} =
             Runner.run(manifest, "mail-capture", QualificationFixture, String.duplicate("c", 32))

    assert_received {:effect, :mail_send}
    refute_received {:effect, _}
  end

  test "an occupied capture port prevents dispatch", %{port: port} do
    workspace = Path.expand("tmp/capture-busy-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)

    manifest =
      QualificationFixture.manifest(workspace, "mail-capture") |> put_in(["fixtures", "mail", "smtp_port"], port)

    QualificationFixture.setup(manifest)
    assert {:error, %Error{}} = Runner.run(manifest, "mail-capture", QualificationFixture, String.duplicate("c", 32))
    refute_received {:effect, _}
  end

  test "an existing outgoing queue prevents opening a transport or sending", %{port: port} do
    workspace = Path.expand("tmp/capture-queued-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf(workspace) end)
    capture_port = unused_port(port)

    manifest =
      QualificationFixture.manifest(workspace, "mail-capture")
      |> put_in(["fixtures", "mail", "smtp_port"], capture_port)

    QualificationFixture.setup(manifest)
    Process.put({QualificationFixture, :mail_idle}, false)
    assert {:error, %Error{}} = Runner.run(manifest, "mail-capture", QualificationFixture, String.duplicate("c", 32))
    refute_received {:effect, _}
    assert {:ok, listener} = :gen_tcp.listen(capture_port, active: false, ip: {127, 0, 0, 1})
    :gen_tcp.close(listener)
  end

  defp connect(port) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :line], 1000)
    assert {:ok, "220 exmc-capture\r\n"} = :gen_tcp.recv(socket, 0, 1000)
    socket
  end

  defp line(socket, value) do
    :ok = :gen_tcp.send(socket, value <> "\r\n")
    {:ok, reply} = :gen_tcp.recv(socket, 0, 1000)
    reply
  end

  defp unused_port(excluded) do
    {:ok, listener} = :gen_tcp.listen(0, active: false, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    if port in [excluded, 41_049], do: unused_port(excluded), else: port
  end
end
