defmodule ExMacOSControl.QualificationFixture do
  @moduledoc false
  alias ExMacOSControl.Automation
  alias ExMacOSControl.Qualification.Host

  def manifest(workspace, profile \\ "notes-crud") do
    bundle = if profile == "notes-crud", do: "com.apple.Notes", else: "com.apple.mail"

    fixtures =
      if profile == "notes-crud",
        do: %{
          "notes" => %{"account_id" => "qa-account", "folder_id" => "qa-folder", "folder_name" => "EXMC-QA-Fixtures"}
        },
        else: %{
          "mail" => %{
            "account_id" => "qa-mail",
            "sender" => "sender@qa.invalid",
            "recipient" => "sink@qa.invalid",
            "smtp_port" => 25_251
          }
        }

    %{
      "version" => 1,
      "expires_at" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601(),
      "workspace" => workspace,
      "host" => %{
        "uid" => 502,
        "username" => "exmc_qa",
        "home" => "/Users/exmc_qa",
        "machine_sha256" => String.duplicate("a", 64),
        "disposable" => true
      },
      "apps" => %{bundle => %{"path" => "/System/Applications/QA.app", "version" => "1", "build" => "1"}},
      "fixtures" => fixtures,
      "limits" => %{
        "deadline_ms" => 5000,
        "max_effects" => 3,
        "max_sends" => if(profile == "notes-crud", do: 0, else: 1),
        "max_bytes" => 65_536
      }
    }
  end

  def setup(manifest) do
    snapshot =
      manifest["host"]
      |> Map.delete("disposable")
      |> Map.merge(%{
        "console_uid" => 502,
        "groups" => ["staff"],
        "session" => "Aqua",
        "workspace" => manifest["workspace"],
        "macos" => "test",
        "elixir" => System.version()
      })

    Process.put({__MODULE__, :snapshot}, snapshot)
    Process.put({__MODULE__, :guards}, 0)
    Process.put({__MODULE__, :note}, nil)
    Process.delete({__MODULE__, :hook})
    Process.delete({__MODULE__, :failure})
    Process.delete({__MODULE__, :dispatch_hook})
    Process.delete({__MODULE__, :mail_idle})
    :ok
  end

  def guard(manifest, _profile, _opts) do
    count = Process.get({__MODULE__, :guards}, 0) + 1
    Process.put({__MODULE__, :guards}, count)
    if hook = Process.get({__MODULE__, :hook}), do: hook.(count)
    snapshot = Process.get({__MODULE__, :snapshot})
    with :ok <- Host.verify(manifest, snapshot), do: {:ok, snapshot}
  end

  def perform(operation, manifest, context, _opts) do
    if hook = Process.get({__MODULE__, :dispatch_hook}), do: hook.(operation, context)
    send(self(), {:effect, operation})
    failure = Process.get({__MODULE__, :failure})

    if failure == operation,
      do: Automation.invalid("private synthetic content"),
      else: perform(operation, manifest, context)
  end

  defp perform(:notes_create, manifest, context) do
    Process.put({__MODULE__, :note}, %{
      title: context.marker,
      plaintext: context.marker,
      folder_id: manifest["fixtures"]["notes"]["folder_id"]
    })

    {:ok, "created-note"}
  end

  defp perform(:notes_update, _manifest, context) do
    Process.put(
      {__MODULE__, :note},
      Map.put(Process.get({__MODULE__, :note}), :plaintext, context.marker <> " changed")
    )

    :ok
  end

  defp perform(:notes_delete, _, _) do
    Process.put({__MODULE__, :note}, nil)
    :ok
  end

  defp perform(:mail_send, manifest, context) do
    fixture = manifest["fixtures"]["mail"]

    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, fixture["smtp_port"], [:binary, active: false, packet: :line], 1000)

    recv(socket)
    exchange(socket, "HELO qa\r\n")
    exchange(socket, "MAIL FROM:<#{fixture["sender"]}>\r\n")
    exchange(socket, "RCPT TO:<#{fixture["recipient"]}>\r\n")
    exchange(socket, "DATA\r\n")
    exchange(socket, "Subject: #{context.marker}\r\n\r\n#{context.marker}\r\n.\r\n")
    exchange(socket, "QUIT\r\n")
    :gen_tcp.close(socket)
    :ok
  end

  def observe(:notes_get, _, _, _), do: {:ok, Process.get({__MODULE__, :note})}
  def observe(:notes_absent, _, _, _), do: {:ok, is_nil(Process.get({__MODULE__, :note}))}
  def observe(:mail_idle, _, _, _), do: {:ok, Process.get({__MODULE__, :mail_idle}, true)}

  defp exchange(socket, line) do
    :gen_tcp.send(socket, line)
    recv(socket)
  end

  defp recv(socket), do: :gen_tcp.recv(socket, 0, 1000)
end
