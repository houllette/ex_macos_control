defmodule ExMacOSControl.Automation do
  @moduledoc false

  alias ExMacOSControl.Error

  @execution [:timeout, :max_output_bytes]
  @keys ~w(id name account_id folder_id list_id calendar_id parent_id title body plaintext
           created_at modified_at completed completed_at due_at reminder_at priority flagged
           start_at end_at all_day recurrence excluded_dates location description url writable
           email status attendees phones emails addresses groups organization first_name last_name
           note vcard subject sender received_at read flagged junk content message_id attachments
           window_id tab_index source text path filename width height size favorite keywords date
           duration position volume muted playing artist album rating tracks persistent_id street city postal_code country country_code scripts trigger_minutes trigger_at essential_properties start_time frame_duration timecode_format
           accepts_input action_count subtitle folder enabled service_type handle participants pid running selection ready_state
           role subrole identifier value attributes actions children truncated bounds busy bundle_id version build dictionary scriptable index label button state current_track unread group_id capacity free_space dimensions resolution color_space bit_depth file_type input_volume alert_volume)a
  @key_map Map.new(@keys, &{Atom.to_string(&1), &1})

  def query(bundle_id, body, params \\ %{}, opts \\ []) do
    with :ok <- options(opts, @execution),
         {:ok, json} <- encode(Map.put(params, :__bundle_id, bundle_id)),
         effective = Keyword.merge([timeout: 30_000, max_output_bytes: 10_485_760], execution_options(opts)),
         {:ok, output} <-
           ExMacOSControl.run_javascript(script(body),
             args: [json],
             timeout: effective[:timeout],
             max_output_bytes: effective[:max_output_bytes]
           ),
         {:ok, %{"exmc" => 1, "result" => result}} <- decode(output) do
      {:ok, normalize(result)}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> invalid("Invalid automation response")
    end
  end

  def action(bundle_id, body, params \\ %{}, opts \\ []) do
    case query(bundle_id, body <> "\nreturn true;", params, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
      _ -> invalid("Application did not acknowledge the operation")
    end
  end

  def options(opts, allowed) do
    cond do
      not keyword_options?(opts) ->
        invalid("Options must be a keyword list")

      Keyword.keys(opts) -- allowed != [] ->
        invalid("Unknown or invalid options")

      not valid_identifiers?(opts) ->
        invalid("Optional resource IDs must be non-empty strings")

      Keyword.has_key?(opts, :timeout) and not valid_timeout?(opts[:timeout]) ->
        invalid("Timeout must be non-negative, :infinity, or nil")

      Keyword.has_key?(opts, :max_output_bytes) and
          not positive_integer?(opts[:max_output_bytes]) ->
        invalid("max_output_bytes must be positive")

      true ->
        :ok
    end
  end

  defp keyword_options?(opts), do: is_list(opts) and Keyword.keyword?(opts)
  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_identifiers?(opts) do
    Enum.all?([:account_id, :folder_id, :album_id, :playlist_id, :shortcut_id], fn key ->
      value = Keyword.get(opts, key)
      is_nil(value) or (is_binary(value) and String.trim(value) != "")
    end)
  end

  defp valid_timeout?(value), do: value in [nil, :infinity] or (is_integer(value) and value >= 0)

  def execution_options(opts), do: ExMacOSControl.execution_options(Keyword.take(opts, @execution))

  def required_string(value, label) do
    if is_binary(value) and String.trim(value) != "" and not String.contains?(value, <<0>>) do
      :ok
    else
      invalid("#{label} must be a non-empty string")
    end
  end

  def page(opts) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    if is_integer(limit) and limit in 1..1000 and is_integer(offset) and offset >= 0 do
      {:ok, %{limit: limit, offset: offset}}
    else
      invalid("limit must be 1..1000 and offset must be non-negative")
    end
  end

  def date(nil), do: {:ok, nil}
  def date(%DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}

  def date(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _offset} -> {:ok, DateTime.to_iso8601(date)}
      _ -> invalid("Dates must include an ISO 8601 timezone")
    end
  end

  def date(_), do: invalid("Dates must be DateTime values or ISO 8601 strings")
  def invalid(message), do: {:error, Error.execution_error(message)}

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> {:ok, encoded}
      _ -> invalid("Input must be JSON serializable")
    end
  end

  defp decode(output) when is_binary(output), do: Jason.decode(output)
  defp decode(_output), do: invalid("Automation result must be JSON text")
  defp normalize(values) when is_list(values), do: Enum.map(values, &normalize/1)

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {Map.get(@key_map, key, key), normalize(value)} end)

  defp normalize(value), do: value

  defp script(body) do
    """
    function run(argv) {
      var input = JSON.parse(argv[0]);
      var app = input.__bundle_id ? Application(input.__bundle_id) : Application.currentApplication();
      function byId(collection, value) {
        var object = collection.byId(value);
        if (!object.exists()) throw new Error('Object not found');
        return object;
      }
      function iso(value) { return value ? new Date(value).toISOString() : null; }
      function page(values) { return values.slice(input.offset || 0, (input.offset || 0) + (input.limit || 100)); }
      var result = (function() { #{body}\n })();
      return JSON.stringify({exmc: 1, result: result === undefined ? null : result});
    }
    """
  end
end
