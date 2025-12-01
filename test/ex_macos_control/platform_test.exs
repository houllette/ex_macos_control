defmodule ExMacOSControl.PlatformTest do
  use ExUnit.Case, async: true

  alias ExMacOSControl.Platform

  describe "macos?/0" do
    test "returns true on macOS" do
      # We can't easily mock :os.type/0 in the same process
      # so we'll test the actual system
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.macos?() == true

        _ ->
          assert Platform.macos?() == false
      end
    end
  end

  describe "os_type/0" do
    test "returns the OS type tuple" do
      # Should return the actual OS type
      expected = :os.type()
      assert Platform.os_type() == expected
    end

    test "returns {:unix, :darwin} on macOS" do
      # This test will only pass on macOS
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.os_type() == {:unix, :darwin}

        _ ->
          # On non-macOS, just verify it returns a valid tuple
          {family, name} = Platform.os_type()
          assert is_atom(family)
          assert is_atom(name)
      end
    end
  end

  describe "validate_macos!/0" do
    test "returns :ok on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.validate_macos!() == :ok

        _ ->
          assert_raise ExMacOSControl.PlatformError, fn ->
            Platform.validate_macos!()
          end
      end
    end

    test "raises PlatformError on non-macOS with helpful message" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS
          :ok

        os_type ->
          error =
            assert_raise ExMacOSControl.PlatformError, fn ->
              Platform.validate_macos!()
            end

          assert error.message =~ "ExMacOSControl requires macOS"
          assert error.message =~ "Detected OS: #{inspect(os_type)}"
      end
    end
  end

  describe "validate_macos/0" do
    test "returns :ok on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.validate_macos() == :ok

        _ ->
          assert {:error, _} = Platform.validate_macos()
      end
    end

    test "returns error tuple on non-macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS
          :ok

        _os_type ->
          assert {:error, error} = Platform.validate_macos()
          assert %ExMacOSControl.PlatformError{} = error
          assert error.message =~ "ExMacOSControl requires macOS"
      end
    end
  end

  describe "osascript_available?/0" do
    test "returns true when osascript is available" do
      case :os.type() do
        {:unix, :darwin} ->
          # On macOS, osascript should be available
          assert Platform.osascript_available?() == true

        _ ->
          # On non-macOS, osascript should not be available
          assert Platform.osascript_available?() == false
      end
    end
  end

  describe "validate_osascript!/0" do
    test "returns :ok when osascript is available" do
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.validate_osascript!() == :ok

        _ ->
          assert_raise ExMacOSControl.PlatformError, fn ->
            Platform.validate_osascript!()
          end
      end
    end

    test "raises PlatformError when osascript is not available" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS (osascript should be available)
          :ok

        _ ->
          error =
            assert_raise ExMacOSControl.PlatformError, fn ->
              Platform.validate_osascript!()
            end

          assert error.message =~ "osascript command not found"
      end
    end
  end

  describe "validate_osascript/0" do
    test "returns :ok when osascript is available" do
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.validate_osascript() == :ok

        _ ->
          assert {:error, _} = Platform.validate_osascript()
      end
    end

    test "returns error tuple when osascript is not available" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS
          :ok

        _ ->
          assert {:error, error} = Platform.validate_osascript()
          assert %ExMacOSControl.PlatformError{} = error
          assert error.message =~ "osascript command not found"
      end
    end
  end

  describe "macos_version/0" do
    test "returns version string on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          assert {:ok, version} = Platform.macos_version()
          assert is_binary(version)
          # Version should be in format like "14.0" or "13.5.1"
          assert version =~ ~r/^\d+\.\d+(\.\d+)?$/

        _ ->
          assert {:error, _} = Platform.macos_version()
      end
    end

    test "returns error on non-macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS
          :ok

        _ ->
          assert {:error, error} = Platform.macos_version()
          assert %ExMacOSControl.PlatformError{} = error
          assert error.message =~ "not running on macOS"
      end
    end
  end

  describe "macos_version!/0" do
    test "returns version string on macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          version = Platform.macos_version!()
          assert is_binary(version)
          assert version =~ ~r/^\d+\.\d+(\.\d+)?$/

        _ ->
          assert_raise ExMacOSControl.PlatformError, fn ->
            Platform.macos_version!()
          end
      end
    end

    test "raises on non-macOS" do
      case :os.type() do
        {:unix, :darwin} ->
          # Skip this test on macOS
          :ok

        _ ->
          assert_raise ExMacOSControl.PlatformError, fn ->
            Platform.macos_version!()
          end
      end
    end
  end

  describe "parse_macos_version/1" do
    test "parses valid version strings" do
      assert Platform.parse_macos_version("14.0") == {:ok, {14, 0, 0}}
      assert Platform.parse_macos_version("13.5.1") == {:ok, {13, 5, 1}}
      assert Platform.parse_macos_version("12.6") == {:ok, {12, 6, 0}}
      assert Platform.parse_macos_version("15.0.0") == {:ok, {15, 0, 0}}
      assert Platform.parse_macos_version("14") == {:ok, {14, 0, 0}}
    end

    test "handles ProductVersion format" do
      # Sometimes sw_vers returns 'ProductVersion:\t14.0'
      assert Platform.parse_macos_version("ProductVersion:\t14.0") == {:ok, {14, 0, 0}}
      assert Platform.parse_macos_version("ProductVersion: 13.5.1") == {:ok, {13, 5, 1}}
    end

    test "returns error for invalid version strings" do
      assert {:error, _} = Platform.parse_macos_version("invalid")
      assert {:error, _} = Platform.parse_macos_version("abc.def")
      assert {:error, _} = Platform.parse_macos_version("")
      assert {:error, _} = Platform.parse_macos_version("14.x")
    end
  end

  describe "compare_version/2" do
    test "compares versions correctly" do
      assert Platform.compare_version({14, 0, 0}, {13, 5, 1}) == :gt
      assert Platform.compare_version({13, 5, 1}, {14, 0, 0}) == :lt
      assert Platform.compare_version({14, 0, 0}, {14, 0, 0}) == :eq
      assert Platform.compare_version({13, 5, 0}, {13, 5, 1}) == :lt
      assert Platform.compare_version({13, 6, 0}, {13, 5, 1}) == :gt
    end
  end

  describe "version_at_least?/1" do
    test "compares against current macOS version" do
      case :os.type() do
        {:unix, :darwin} ->
          # Should work on macOS
          # We know macOS 10.15+ is required for modern osascript
          assert Platform.version_at_least?({10, 15, 0}) == true
          # Very old version should return false
          assert Platform.version_at_least?({10, 0, 0}) == true
          # Future version should return false
          assert Platform.version_at_least?({99, 0, 0}) == false

        _ ->
          # On non-macOS, should return false
          assert Platform.version_at_least?({10, 15, 0}) == false
      end
    end

    test "handles version tuples of different lengths" do
      case :os.type() do
        {:unix, :darwin} ->
          assert Platform.version_at_least?({10, 15}) == true
          assert Platform.version_at_least?({99}) == false

        _ ->
          assert Platform.version_at_least?({10, 15}) == false
      end
    end
  end
end
