defmodule ExMacOSControl.Qualification.Native do
  @moduledoc false
  alias ExMacOSControl.{Automation, Capabilities, Mail, Notes, OSAScriptAdapter, Permissions}
  alias ExMacOSControl.Qualification.{Host, Manifest}

  def guard(manifest, profile, opts) do
    bundle = Manifest.bundle(profile)
    expected = manifest["apps"][bundle]

    with true <- Application.get_env(:ex_macos_control, :adapter, OSAScriptAdapter) == OSAScriptAdapter,
         {:ok, snapshot} <- Host.snapshot(),
         :ok <- Host.verify(manifest, snapshot),
         {:ok, app} <- Capabilities.app(bundle, Keyword.put(opts, :paths, [Path.dirname(expected["path"])])),
         true <- app.path == expected["path"] and app.version == expected["version"] and app.build == expected["build"],
         {:ok, :granted} <- Permissions.preflight_automation(bundle, opts),
         {:ok, true} <- fixture(manifest, profile, opts) do
      {:ok, snapshot}
    else
      _ -> Automation.invalid("Qualification host, app, permission, or fixture preflight failed")
    end
  end

  def perform(operation, manifest, context, opts) do
    with {:ok, effective} <- effect_options(context, opts), do: dispatch(operation, manifest, context, effective)
  end

  defp dispatch(:notes_create, manifest, context, opts),
    do:
      Notes.create_note(
        [title: context.marker, body: "<p>#{context.marker}</p>"],
        Keyword.put(opts, :folder_id, manifest["fixtures"]["notes"]["folder_id"])
      )

  defp dispatch(:notes_update, manifest, context, opts) do
    with :ok <- owned_note(manifest, context, opts),
         {:ok, effective} <- effect_options(context, opts) do
      Notes.update_note(context.id, [body: "<p>#{context.marker}</p><p>changed</p>"], effective)
    end
  end

  defp dispatch(:notes_delete, manifest, context, opts) do
    with :ok <- owned_note(manifest, context, opts),
         {:ok, effective} <- effect_options(context, opts),
         do: Notes.delete_note(context.id, effective)
  end

  defp dispatch(:mail_send, manifest, context, opts) do
    fixture = manifest["fixtures"]["mail"]

    Mail.send_email(
      Keyword.merge(opts,
        to: fixture["recipient"],
        sender: fixture["sender"],
        subject: context.marker,
        body: context.marker
      )
    )
  end

  defp effect_options(context, opts) do
    remaining = context.deadline - System.monotonic_time(:millisecond)

    with true <- remaining > 0,
         {:ok, expires, _} <- DateTime.from_iso8601(context.expires_at),
         :gt <- DateTime.compare(expires, DateTime.utc_now()) do
      {:ok, Keyword.put(opts, :timeout, min(opts[:timeout], remaining))}
    else
      _ -> Automation.invalid("Effect lease expired before dispatch")
    end
  end

  def observe(:notes_get, manifest, context, opts) do
    with :ok <- owned_note(manifest, context, opts), do: Notes.get_note(context.id, opts)
  end

  def observe(:notes_absent, manifest, context, opts) do
    Automation.query(
      "com.apple.Notes",
      "return !byId(app.folders,input.folder).notes().some(function(o){return o.id()===input.id;});",
      %{folder: manifest["fixtures"]["notes"]["folder_id"], id: context.id},
      opts
    )
  end

  def observe(:mail_idle, _manifest, _context, opts),
    do: Automation.query("com.apple.mail", "return app.outgoingMessages.length===0;", %{}, opts)

  defp owned_note(manifest, context, opts) do
    case Automation.query(
           "com.apple.Notes",
           "var o=byId(byId(app.folders,input.folder).notes,input.id);return o.name()===input.marker&&o.container().id()===input.folder;",
           %{folder: manifest["fixtures"]["notes"]["folder_id"], id: context.id, marker: context.marker},
           opts
         ) do
      {:ok, true} -> :ok
      _ -> Automation.invalid("Note ownership differs; refusing mutation or cleanup")
    end
  end

  @doc false
  def fixture(manifest, "notes-crud", opts) do
    Automation.query(
      "com.apple.Notes",
      "var f=input.fixture,accounts=app.accounts();if(accounts.length!==1||accounts[0].id()!==f.account_id)return false;var o=accounts[0].folders.byId(f.folder_id);return o.exists()&&o.name()===f.folder_name&&o.shared()===false&&o.container().id()===f.account_id;",
      %{fixture: manifest["fixtures"]["notes"]},
      opts
    )
  end

  def fixture(manifest, "mail-capture", opts) do
    Automation.query(
      "com.apple.mail",
      "var f=input.fixture,accounts=app.accounts(),servers=app.smtpServers();if(accounts.length!==1||servers.length!==1)return false;var a=accounts[0],s=a.deliveryAccount(),addresses=a.emailAddresses();return a.id()===f.account_id&&a.enabled()===true&&addresses.length===1&&addresses[0]===f.sender&&s.name()===servers[0].name()&&s.enabled()===true&&s.serverName()==='127.0.0.1'&&s.port()===f.smtp_port&&s.usesSsl()===false&&s.authentication()==='none';",
      %{fixture: manifest["fixtures"]["mail"]},
      opts
    )
  end
end
