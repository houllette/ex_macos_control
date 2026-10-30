defmodule ExMacOSControl.Qualification.Manifest do
  @moduledoc false
  import Bitwise
  alias ExMacOSControl.Automation

  @profiles %{"notes-crud" => "com.apple.Notes", "mail-capture" => "com.apple.mail"}
  @fields ~w(version expires_at workspace host apps fixtures limits)

  def load(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size, mode: mode}} when size <= 65_536 <- File.lstat(path),
         true <- (mode &&& 0o077) == 0,
         {:ok, raw} <- File.read(path),
         {:ok, ordered} <- Jason.decode(raw, objects: :ordered_objects),
         true <- unique_keys?(ordered),
         {:ok, map} <- Jason.decode(raw) do
      {:ok, map}
    else
      _ -> invalid("Manifest must be private, unambiguous JSON in a regular file of at most 64 KiB")
    end
  end

  def load(_), do: invalid("Manifest path must be a string")

  defp unique_keys?(%Jason.OrderedObject{values: values}) do
    keys = Enum.map(values, &elem(&1, 0))
    length(keys) == MapSet.size(MapSet.new(keys)) and Enum.all?(values, fn {_, value} -> unique_keys?(value) end)
  end

  defp unique_keys?(values) when is_list(values), do: Enum.all?(values, &unique_keys?/1)
  defp unique_keys?(_), do: true

  def validate(map, profile, now \\ DateTime.utc_now()) do
    with :ok <- shape(map, @fields),
         true <- map["version"] == 1,
         {:ok, bundle} <- fetch_profile(profile),
         {:ok, expires} <- expires(map["expires_at"]),
         seconds = DateTime.diff(expires, now),
         true <- seconds > 0 and seconds <= 86_400,
         true <- absolute?(map["workspace"]),
         :ok <- host(map["host"]),
         :ok <- apps(map["apps"], bundle),
         :ok <- limits(map["limits"]),
         :ok <- profile_limits(profile, map["limits"]),
         :ok <- fixture(profile, map["fixtures"]) do
      {:ok, map}
    else
      {:error, %ExMacOSControl.Error{}} = error -> error
      _ -> invalid("Invalid manifest, expired authorization, or authorization longer than 24 hours")
    end
  end

  def bundle(profile), do: Map.fetch!(@profiles, profile)
  def profiles, do: Map.keys(@profiles)

  defp expires(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> {:ok, date}
      _ -> invalid("Expiry must be an ISO 8601 timestamp")
    end
  end

  defp expires(_), do: invalid("Expiry must be an ISO 8601 timestamp")

  defp profile_limits("notes-crud", %{"max_effects" => effects, "max_sends" => 0}) when effects >= 3, do: :ok
  defp profile_limits("mail-capture", %{"max_sends" => 1}), do: :ok
  defp profile_limits(_, _), do: invalid("Profile budget must cover the fixed case; only capture may send once")

  defp fetch_profile(profile) do
    case Map.fetch(@profiles, profile) do
      {:ok, bundle} -> {:ok, bundle}
      _ -> invalid("Profile is disabled or unknown; external sending and recording are not enabled")
    end
  end

  defp host(map) do
    with :ok <- shape(map, ~w(uid username home machine_sha256 disposable)),
         true <- is_integer(map["uid"]) and map["uid"] >= 501,
         true <- text?(map["username"]) and map["username"] != "root",
         true <- absolute?(map["home"]),
         true <- is_binary(map["machine_sha256"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, map["machine_sha256"]),
         true <- map["disposable"] == true do
      :ok
    else
      _ -> invalid("Manifest must identify a disposable non-root macOS user and machine")
    end
  end

  defp apps(map, bundle) do
    with :ok <- shape(map, [bundle]),
         :ok <- shape(map[bundle], ~w(path version build)),
         true <- absolute?(map[bundle]["path"]),
         true <- text?(map[bundle]["version"]) and text?(map[bundle]["build"]) do
      :ok
    else
      _ -> invalid("Profile requires an exact app path, version, and build")
    end
  end

  defp limits(map) do
    with :ok <- shape(map, ~w(deadline_ms max_effects max_sends max_bytes)),
         true <- integer_in?(map["deadline_ms"], 1000..120_000),
         true <- integer_in?(map["max_effects"], 1..8),
         true <- integer_in?(map["max_sends"], 0..1),
         true <- integer_in?(map["max_bytes"], 1024..1_048_576) do
      :ok
    else
      _ -> invalid("Limits must bound runtime, effects, sends, and output bytes")
    end
  end

  defp fixture("notes-crud", map) do
    with :ok <- shape(map, ["notes"]),
         :ok <- shape(map["notes"], ~w(account_id folder_id folder_name)),
         true <- Enum.all?(~w(account_id folder_id folder_name), &text?(map["notes"][&1])),
         true <- String.starts_with?(map["notes"]["folder_name"], "EXMC-QA-") do
      :ok
    else
      _ -> invalid("Notes needs an explicit account and an EXMC-QA- folder identity")
    end
  end

  defp fixture("mail-capture", map) do
    with :ok <- shape(map, ["mail"]),
         :ok <- shape(map["mail"], ~w(account_id sender recipient smtp_port)),
         true <- text?(map["mail"]["account_id"]),
         true <- capture_address?(map["mail"]["sender"]) and capture_address?(map["mail"]["recipient"]),
         true <- integer_in?(map["mail"]["smtp_port"], 1024..65_535),
         true <- map["mail"]["smtp_port"] != 41_049 do
      :ok
    else
      _ -> invalid("Mail capture requires explicit .invalid addresses and a nonprivileged loopback SMTP port")
    end
  end

  def shape(map, fields) when is_map(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(fields), do: :ok, else: invalid("Unknown or missing manifest fields")
  end

  def shape(_, _), do: invalid("Manifest sections must be objects")
  defp integer_in?(value, range), do: is_integer(value) and value in range
  defp absolute?(value), do: text?(value) and Path.type(value) == :absolute and Path.expand(value) == value
  defp text?(value), do: is_binary(value) and String.trim(value) != "" and not String.contains?(value, <<0>>)

  defp capture_address?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z0-9][a-z0-9._+-]*@[a-z0-9.-]+\.invalid\z/, value)

  defp invalid(message), do: Automation.invalid(message)
end
