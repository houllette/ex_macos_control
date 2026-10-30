defmodule ExMacOSControl.TV do
  @moduledoc "TV playback, library metadata and playlists, addressed by persistent IDs. Protected media remains subject to the TV app."
  use ExMacOSControl.Media, bundle_id: "com.apple.TV"
end
