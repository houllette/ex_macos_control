# Configure ExUnit
ExUnit.start()

# Exclude integration tests by default
# Run with: mix test --include integration
ExUnit.configure(exclude: [integration: true, desktop: true, shortcut: true])

# Define mock for adapter
Mox.defmock(ExMacOSControl.AdapterMock, for: ExMacOSControl.Adapter)

# Display platform information at test startup
platform_info = """

================================================================================
Test Environment Information
================================================================================
Platform: #{inspect(:os.type())}
macOS: #{ExMacOSControl.TestHelpers.macos?()}
osascript available: #{ExMacOSControl.TestHelpers.osascript_available?()}
Native integration prerequisites available: #{ExMacOSControl.TestHelpers.should_run_integration_tests?()}

To run native checks: mix test --include integration
Desktop-mutating tests additionally require --include desktop (use an isolated session)
================================================================================
"""

IO.puts(platform_info)
