defmodule ExMacOSControl.Qualification.Host do
  @moduledoc false
  alias ExMacOSControl.{Automation, Command}

  def snapshot do
    with true <- :os.type() == {:unix, :darwin},
         {:ok, uid} <- command("/usr/bin/id", ["-u"]),
         {:ok, username} <- command("/usr/bin/id", ["-un"]),
         {:ok, groups} <- command("/usr/bin/id", ["-Gn"]),
         {:ok, session} <- command("/bin/launchctl", ["managername"]),
         {:ok, machine} <- command("/usr/sbin/ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"]),
         [_, uuid] <- Regex.run(~r/"IOPlatformUUID"\s*=\s*"([^"]+)"/, machine),
         {:ok, %{uid: console_uid}} <- File.stat("/dev/console"),
         {:ok, os} <- command("/usr/bin/sw_vers", ["-productVersion"]) do
      {:ok,
       %{
         "uid" => String.to_integer(uid),
         "username" => username,
         "groups" => String.split(groups),
         "session" => session,
         "console_uid" => console_uid,
         "home" => System.user_home!(),
         "machine_sha256" => Base.encode16(:crypto.hash(:sha256, uuid), case: :lower),
         "workspace" => File.cwd!(),
         "macos" => os,
         "elixir" => System.version(),
         "otp" => to_string(:erlang.system_info(:otp_release))
       }}
    else
      _ -> Automation.invalid("Live qualification requires an identifiable macOS desktop session")
    end
  end

  def verify(manifest, snapshot) do
    host = Map.delete(manifest["host"], "disposable")
    matches = Enum.all?(host, fn {key, value} -> snapshot[key] == value end)

    if matches and standard_user?(snapshot) and snapshot["session"] == "Aqua" and
         snapshot["uid"] == snapshot["console_uid"] and
         snapshot["workspace"] == manifest["workspace"],
       do: :ok,
       else: Automation.invalid("User, machine, workspace, or active desktop differs from the manifest")
  end

  defp standard_user?(%{"groups" => groups}) when is_list(groups), do: "admin" not in groups
  defp standard_user?(_), do: false

  # One port for all qualifying workspaces; no clients or commands are accepted.
  def lock, do: :gen_tcp.listen(41_049, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: false])
  def unlock(socket), do: :gen_tcp.close(socket)

  defp command(path, args) do
    case Command.run(path, args, timeout: 2000, max_output_bytes: 65_536) do
      {:ok, %{exit_status: 0, stdout: value}} -> {:ok, String.trim(value)}
      _ -> Automation.invalid("Unable to inspect qualification host")
    end
  end
end
