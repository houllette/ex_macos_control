defmodule ExMacOSControl.PermissionsTest do
  use ExUnit.Case, async: true

  import Mox
  import ExUnit.CaptureIO

  alias ExMacOSControl.{Error, Permissions}

  setup :verify_on_exit!

  setup do
    stub(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
      {:ok, "granted"}
    end)

    :ok
  end

  describe "check_accessibility/0" do
    test "returns :granted when permission is granted" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Events"
        assert script =~ "set frontmost to true"
        {:ok, "granted"}
      end)

      assert {:ok, :granted} = Permissions.check_accessibility()
    end

    test "returns :not_granted when script returns not_granted" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:ok, "not_granted"}
      end)

      assert {:ok, :not_granted} = Permissions.check_accessibility()
    end

    test "detects permission error from error message containing 'not allowed'" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :permission_denied, message: "not allowed assistive access"}}
      end)

      assert {:ok, :not_granted} = Permissions.check_accessibility()
    end

    test "returns error for other failures" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error, message: "something else"}}
      end)

      assert {:error, %Error{type: :execution_error}} = Permissions.check_accessibility()
    end

    test "generates correct AppleScript for accessibility check" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"System Events\""
        assert script =~ "set frontmost to true"
        assert script =~ "return \"granted\""
        assert script =~ "not allowed assistive access"
        {:ok, "granted"}
      end)

      Permissions.check_accessibility()
    end
  end

  describe "check_automation/1" do
    test "returns :granted when permission is granted" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Safari"
        assert script =~ "get name"
        {:ok, "granted"}
      end)

      assert {:ok, :granted} = Permissions.check_automation("Safari")
    end

    test "returns :not_granted when script returns not_granted" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "Finder"
        {:ok, "not_granted"}
      end)

      assert {:ok, :not_granted} = Permissions.check_automation("Finder")
    end

    test "escapes quotes in app name" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ ~s(App\\\"Name)
        {:ok, "granted"}
      end)

      Permissions.check_automation(~s(App"Name))
    end

    test "detects 'not allowed' error message" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :permission_denied, message: "not allowed to send keystrokes"}}
      end)

      assert {:ok, :not_granted} = Permissions.check_automation("App")
    end

    test "detects 'not authorized' error message" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :permission_denied, message: "not authorized to control App"}}
      end)

      assert {:ok, :not_granted} = Permissions.check_automation("App")
    end

    test "returns error for other failures" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error, message: "unknown error"}}
      end)

      assert {:error, %Error{}} = Permissions.check_automation("App")
    end

    test "generates correct AppleScript for automation check" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "tell application \"Mail\""
        assert script =~ "get name"
        assert script =~ "return \"granted\""
        assert script =~ "not allowed"
        assert script =~ "not authorized"
        {:ok, "granted"}
      end)

      Permissions.check_automation("Mail")
    end

    test "handles different app names correctly" do
      apps = ["Safari", "Finder", "Mail", "Messages", "Terminal"]

      Enum.each(apps, fn app ->
        expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
          assert script =~ app
          {:ok, "granted"}
        end)

        assert {:ok, :granted} = Permissions.check_automation(app)
      end)
    end
  end

  describe "show_accessibility_help/0" do
    test "prints helpful instructions" do
      output =
        capture_io(fn ->
          Permissions.show_accessibility_help()
        end)

      assert output =~ "Accessibility Permission Required"
      assert output =~ "Privacy & Security"
      assert output =~ "Accessibility"
      assert output =~ "lock icon"
    end

    test "includes system-specific settings name" do
      output =
        capture_io(fn ->
          Permissions.show_accessibility_help()
        end)

      # Should mention either System Settings or System Preferences
      assert output =~ "System Settings" or output =~ "System Preferences"
    end

    test "includes quick shortcut command" do
      output =
        capture_io(fn ->
          Permissions.show_accessibility_help()
        end)

      assert output =~ "open_accessibility_preferences()"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert :ok = Permissions.show_accessibility_help()
      end)
    end

    test "includes step-by-step instructions" do
      output =
        capture_io(fn ->
          Permissions.show_accessibility_help()
        end)

      assert output =~ "1."
      assert output =~ "2."
      assert output =~ "3."
    end
  end

  describe "show_automation_help/1" do
    test "prints helpful instructions with app name" do
      output =
        capture_io(fn ->
          Permissions.show_automation_help("Safari")
        end)

      assert output =~ "Automation Permission Required"
      assert output =~ "Safari"
      assert output =~ "Privacy & Security"
      assert output =~ "Automation"
    end

    test "includes the target app name in instructions" do
      output =
        capture_io(fn ->
          Permissions.show_automation_help("Finder")
        end)

      assert output =~ "Finder"
      assert output =~ "control Finder"
    end

    test "includes quick shortcut command" do
      output =
        capture_io(fn ->
          Permissions.show_automation_help("Mail")
        end)

      assert output =~ "open_automation_preferences()"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert :ok = Permissions.show_automation_help("Messages")
      end)
    end

    test "handles different app names" do
      apps = ["Safari", "Finder", "Mail", "Messages"]

      Enum.each(apps, fn app ->
        output =
          capture_io(fn ->
            Permissions.show_automation_help(app)
          end)

        assert output =~ app
      end)
    end
  end

  describe "open_accessibility_preferences/0" do
    test "opens accessibility settings via AppleScript" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Settings"
        assert script =~ "activate"
        assert script =~ "com.apple.preference.security"
        assert script =~ "Privacy_Accessibility"
        assert script =~ "reveal pane id"
        assert script =~ "reveal anchor"
        {:ok, ""}
      end)

      assert :ok = Permissions.open_accessibility_preferences()
    end

    test "returns error on failure" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error, message: "failed"}}
      end)

      assert {:error, %Error{type: :execution_error}} =
               Permissions.open_accessibility_preferences()
    end

    test "includes delay for UI to load" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "delay 0.5"
        {:ok, ""}
      end)

      Permissions.open_accessibility_preferences()
    end
  end

  describe "open_automation_preferences/0" do
    test "opens automation settings via AppleScript" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "System Settings"
        assert script =~ "activate"
        assert script =~ "com.apple.preference.security"
        assert script =~ "Privacy_Automation"
        assert script =~ "reveal pane id"
        assert script =~ "reveal anchor"
        {:ok, ""}
      end)

      assert :ok = Permissions.open_automation_preferences()
    end

    test "returns error on failure" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn _script ->
        {:error, %Error{type: :execution_error, message: "failed"}}
      end)

      assert {:error, %Error{}} = Permissions.open_automation_preferences()
    end

    test "includes delay for UI to load" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, fn script ->
        assert script =~ "delay 0.5"
        {:ok, ""}
      end)

      Permissions.open_automation_preferences()
    end
  end

  describe "check_all/0" do
    test "checks multiple permissions and returns status map" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, 5, fn script ->
        cond do
          script =~ "System Events" -> {:ok, "granted"}
          script =~ "Safari" -> {:ok, "not_granted"}
          script =~ "Finder" -> {:ok, "granted"}
          script =~ "Mail" -> {:ok, "granted"}
          script =~ "Messages" -> {:ok, "not_granted"}
        end
      end)

      statuses = Permissions.check_all()

      assert statuses.accessibility == :granted
      assert statuses.safari_automation == :not_granted
      assert statuses.finder_automation == :granted
      assert statuses.mail_automation == :granted
      assert statuses.messages_automation == :not_granted
    end

    test "handles errors gracefully" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, 5, fn _script ->
        {:error, %Error{type: :execution_error, message: "failed"}}
      end)

      statuses = Permissions.check_all()

      assert statuses.accessibility == :error
      assert statuses.safari_automation == :error
      assert statuses.finder_automation == :error
      assert statuses.mail_automation == :error
      assert statuses.messages_automation == :error
    end

    test "returns map with all expected keys" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, 5, fn _script ->
        {:ok, "granted"}
      end)

      statuses = Permissions.check_all()

      assert Map.has_key?(statuses, :accessibility)
      assert Map.has_key?(statuses, :safari_automation)
      assert Map.has_key?(statuses, :finder_automation)
      assert Map.has_key?(statuses, :mail_automation)
      assert Map.has_key?(statuses, :messages_automation)
    end

    test "handles mixed permission states" do
      expect(ExMacOSControl.AdapterMock, :run_applescript, 5, fn script ->
        cond do
          script =~ "System Events" -> {:ok, "granted"}
          script =~ "Safari" -> {:error, %Error{message: "not allowed"}}
          script =~ "Finder" -> {:ok, "granted"}
          script =~ "Mail" -> {:ok, "not_granted"}
          script =~ "Messages" -> {:error, %Error{message: "unknown"}}
        end
      end)

      statuses = Permissions.check_all()

      assert statuses.accessibility == :granted
      assert statuses.safari_automation == :not_granted
      assert statuses.finder_automation == :granted
      assert statuses.mail_automation == :not_granted
      assert statuses.messages_automation == :error
    end
  end
end
