# Configure ExUnit
ExUnit.start()

# Exclude integration tests by default
# Run with: mix test --include integration
ExUnit.configure(exclude: [integration: true])

# Define mock for adapter
Mox.defmock(ExMacOSControl.AdapterMock, for: ExMacOSControl.Adapter)

# Load test support files
Code.require_file("test/support/test_helpers.ex")
Code.require_file("test/support/adapter_factory.ex")

# Display platform information at test startup
platform_info = """

================================================================================
Test Environment Information
================================================================================
Platform: #{inspect(:os.type())}
macOS: #{ExMacOSControl.TestHelpers.macos?()}
osascript available: #{ExMacOSControl.TestHelpers.osascript_available?()}
Integration tests enabled: #{ExMacOSControl.TestHelpers.should_run_integration_tests?()}

To run integration tests: mix test --include integration
================================================================================
"""

IO.puts(platform_info)
