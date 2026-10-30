defmodule ExMacOSControl.StandardAdditions do
  @moduledoc "Clipboard, dialogs, notifications, speech, volume and system information. Interactive commands require a logged-in desktop session."
  alias ExMacOSControl.Automation

  def clipboard(opts \\ []), do: query("return String(app.theClipboard());", %{}, opts)

  def set_clipboard(text, opts \\ []) when is_binary(text),
    do: action("app.setTheClipboardTo(input.text);", %{text: text}, opts)

  def notify(text, opts \\ []) do
    with :ok <- Automation.options(opts, [:title, :subtitle, :sound, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(text, "Notification text") do
      params = %{
        text: text,
        title: Keyword.get(opts, :title, "ExMacOSControl"),
        subtitle: Keyword.get(opts, :subtitle, ""),
        sound: opts[:sound]
      }

      action(
        "var options={withTitle:input.title,subtitle:input.subtitle}; if(input.sound) options.soundName=input.sound; app.displayNotification(input.text,options);",
        params,
        Automation.execution_options(opts)
      )
    end
  end

  def dialog(text, opts \\ []) do
    with :ok <-
           Automation.options(opts, [
             :title,
             :buttons,
             :default_button,
             :default_answer,
             :hidden_answer,
             :timeout,
             :max_output_bytes
           ]),
         :ok <- Automation.required_string(text, "Dialog text"),
         buttons = Keyword.get(opts, :buttons, ["Cancel", "OK"]),
         true <- is_list(buttons) and length(buttons) in 1..3 and Enum.all?(buttons, &is_binary/1),
         true <- is_boolean(Keyword.get(opts, :hidden_answer, false)) do
      params = %{
        text: text,
        title: Keyword.get(opts, :title, "ExMacOSControl"),
        buttons: buttons,
        default_button: Keyword.get(opts, :default_button, List.last(buttons)),
        default_answer: opts[:default_answer],
        hidden_answer: Keyword.get(opts, :hidden_answer, false)
      }

      query(
        "var options={withTitle:input.title,buttons:input.buttons,defaultButton:input.default_button}; if(input.default_answer!==null){options.defaultAnswer=input.default_answer;options.hiddenAnswer=input.hidden_answer;} var r=app.displayDialog(input.text,options); return {button:r.buttonReturned,text:r.textReturned===undefined?null:r.textReturned};",
        params,
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Dialog buttons must contain one to three strings")
    end
  end

  def choose_files(opts \\ []), do: chooser("chooseFile", opts)
  def choose_folder(opts \\ []), do: chooser("chooseFolder", opts)

  def say(text, opts \\ []) do
    with :ok <- Automation.options(opts, [:voice, :rate, :timeout, :max_output_bytes]),
         :ok <- Automation.required_string(text, "Speech text"),
         true <- is_nil(opts[:rate]) or (is_integer(opts[:rate]) and opts[:rate] > 0) do
      action(
        "var options={}; if(input.voice) options.using=input.voice; if(input.rate) options.speakingRate=input.rate; app.say(input.text,options);",
        %{text: text, voice: opts[:voice], rate: opts[:rate]},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("Speech rate must be a positive integer")
    end
  end

  def volume(opts \\ []),
    do:
      query(
        "var v=app.getVolumeSettings(); return {volume:v.outputVolume,input_volume:v.inputVolume,alert_volume:v.alertVolume,muted:v.outputMuted};",
        %{},
        opts
      )

  def set_volume(value, opts \\ []) when is_integer(value) and value in 0..100 do
    action("app.setVolume(null,{outputVolume:input.volume});", %{volume: value}, opts)
  end

  def set_muted(value, opts \\ []) when is_boolean(value),
    do: action("app.setVolume(null,{outputMuted:input.muted});", %{muted: value}, opts)

  def system_info(opts \\ []), do: query("return app.systemInfo();", %{}, opts)

  def path_to(location, opts \\ [])
      when location in [:home, :temporary, :desktop, :documents, :downloads, :applications, :library] do
    expression =
      case location do
        :home ->
          "$.NSHomeDirectory().js"

        :temporary ->
          "$.NSTemporaryDirectory().js"

        value ->
          "$.NSFileManager.defaultManager.URLsForDirectoryInDomains($.#{%{desktop: "NSDesktopDirectory", documents: "NSDocumentDirectory", downloads: "NSDownloadsDirectory", applications: "NSApplicationDirectory", library: "NSLibraryDirectory"}[value]}, $.NSUserDomainMask).firstObject.path.js"
      end

    Automation.query(nil, "ObjC.import('Foundation'); return #{expression};", %{}, opts)
  end

  defp chooser(command, opts) do
    with :ok <- Automation.options(opts, [:prompt, :multiple, :timeout, :max_output_bytes]),
         true <- is_boolean(Keyword.get(opts, :multiple, false)) do
      query(
        "var r=app.#{command}({withPrompt:input.prompt,multipleSelectionsAllowed:input.multiple}); return input.multiple ? r.map(String) : String(r);",
        %{prompt: Keyword.get(opts, :prompt, "Choose"), multiple: Keyword.get(opts, :multiple, false)},
        Automation.execution_options(opts)
      )
    else
      {:error, _} = error -> error
      _ -> Automation.invalid("multiple must be a boolean")
    end
  end

  defp query(body, params, opts), do: Automation.query(nil, "app.includeStandardAdditions=true; " <> body, params, opts)

  defp action(body, params, opts),
    do: Automation.action(nil, "app.includeStandardAdditions=true; " <> body, params, opts)
end
