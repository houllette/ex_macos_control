defmodule ExMacOSControl.Music do
  @moduledoc "Music playback, track metadata and playlists. IDs are persistent IDs; streaming and account availability remain app-controlled."
  use ExMacOSControl.Media, bundle_id: "com.apple.Music"
end
