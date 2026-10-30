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

    stub(ExMacOSControl.AdapterMock, :run_javascript, fn _script -> {:ok, "granted"} end)

    stub(ExMacOSControl.AdapterMock, :run_javascript, fn _script, _opts -> {:ok, ~s({"exmc":1,"result":0})} end)
    :ok
  end

  describe "check_accessibility/0" do
    test "returns :granted when permission is granted" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn script ->
        assert script =~ "AXIsProcessTrusted()"
        {:ok, "granted"}
      end)

      assert {:ok, :granted} = Permissions.check_accessibility()
    end

    test "returns :not_granted when script returns not_granted" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _script ->
        {:ok, "not_granted"}
      end)

      assert {:ok, :not_granted} = Permissions.check_accessibility()
    end

    test "detects permission error from error message containing 'not allowed'" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _script ->
        {:error, %Error{type: :permission_denied, message: "not allowed assistive access"}}
      end)

      assert {:ok, :not_granted} = Permissions.check_accessibility()
    end

    test "returns error for other failures" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _script ->
        {:error, %Error{type: :execution_error, message: "something else"}}
      end)

      assert {:error, %Error{type: :execution_error}} = Permissions.check_accessibility()
    end

    test "recognizes structured permission errors without relying on English text" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _script ->
        {:error, %Error{type: :permission_denied, message: "Zugriff verweigert"}}
      end)

      assert {:ok, :not_granted} = Permissions.check_accessibility()
    end

    test "queries caller trust without requesting permissions or changing focus" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn script ->
        assert script =~ "ObjC.import('ApplicationServices')"
        assert script =~ "AXIsProcessTrusted()"
        refute script =~ "AXIsProcessTrustedWithOptions"
        refute script =~ "UI elements enabled"
        refute script =~ "set frontmost"
        {:ok, "granted"}
      end)

      Permissions.check_accessibility()
    end
  end

  describe "check_automation/1" do
    test "checks wildcard permission without prompting and keeps identity in argv" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn script, opts ->
        assert script =~ "AEDeterminePermissionToAutomateTarget"
        assert script =~ "0x2a2a2a2a"
        refute script =~ "get name"
        assert %{"identity" => "Safari", "prompt" => false} = opts[:args] |> hd() |> Jason.decode!()
        {:ok, ~s({"exmc":1,"result":0})}
      end)

      assert {:ok, :granted} = Permissions.check_automation("Safari")
    end

    test "distinguishes denied, consent required, stopped and unavailable targets" do
      for {code, status} <- [
            {-1743, :denied},
            {-1744, :requires_consent},
            {-600, :not_running},
            {-10_814, :unavailable},
            {-1, :unknown}
          ] do
        expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
          {:ok, Jason.encode!(%{exmc: 1, result: code})}
        end)

        assert {:ok, ^status} = Permissions.preflight_automation("com.apple.finder")
      end
    end

    test "legacy check maps consent states but does not invent grants for stopped apps" do
      for code <- [-1743, -1744] do
        expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
          {:ok, Jason.encode!(%{exmc: 1, result: code})}
        end)

        assert {:ok, :not_granted} = Permissions.check_automation("App")
      end

      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ -> {:ok, ~s({"exmc":1,"result":-600})} end)
      assert {:error, %Error{message: message}} = Permissions.check_automation("App")
      assert message =~ "unknown"
    end

    test "prompting requires the explicit request method" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, opts ->
        assert %{"prompt" => true} = opts[:args] |> hd() |> Jason.decode!()
        {:ok, ~s({"exmc":1,"result":0})}
      end)

      assert {:ok, :granted} = Permissions.request_automation("com.apple.finder")
    end

    test "propagates execution failures" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _, _ ->
        {:error, Error.execution_error("Bridge unavailable")}
      end)

      assert {:error, %Error{}} = Permissions.check_automation("App")
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
    test "checks multiple permissions and preserves mixed results" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, 4, fn _, opts ->
        id = opts[:args] |> hd() |> Jason.decode!() |> Map.fetch!("identity")
        code = if id in ["Safari", "Messages"], do: -1744, else: 0
        {:ok, Jason.encode!(%{exmc: 1, result: code})}
      end)

      assert %{
               accessibility: :granted,
               safari_automation: :not_granted,
               finder_automation: :granted,
               mail_automation: :granted,
               messages_automation: :not_granted
             } = Permissions.check_all()
    end

    test "handles errors without fabricating a permission state" do
      expect(ExMacOSControl.AdapterMock, :run_javascript, fn _ -> {:error, Error.execution_error("failed")} end)
      expect(ExMacOSControl.AdapterMock, :run_javascript, 4, fn _, _ -> {:error, Error.execution_error("failed")} end)
      assert Enum.all?(Permissions.check_all(), fn {_, state} -> state == :error end)
    end
  end
end
