defmodule ExMacOSControl.PermissionsIntegrationTest do
  use ExUnit.Case, async: false

  alias ExMacOSControl.{Permissions, TestHelpers}

  @moduletag :integration

  setup do
    TestHelpers.skip_unless_integration()

    # Use real adapter
    original_adapter = Application.get_env(:ex_macos_control, :adapter)
    Application.put_env(:ex_macos_control, :adapter, ExMacOSControl.OSAScriptAdapter)

    on_exit(fn ->
      if original_adapter do
        Application.put_env(:ex_macos_control, :adapter, original_adapter)
      else
        Application.delete_env(:ex_macos_control, :adapter)
      end
    end)

    :ok
  end

  describe "check_accessibility/0" do
    @tag :integration
    test "returns a valid status" do
      result = Permissions.check_accessibility()
      assert {:ok, status} = result
      assert status in [:granted, :not_granted]
    end

    @tag :integration
    test "result is consistent across multiple calls" do
      result1 = Permissions.check_accessibility()
      result2 = Permissions.check_accessibility()
      assert result1 == result2
    end
  end

  describe "check_automation/1" do
    @tag :integration
    test "checks Safari automation permission" do
      result = Permissions.check_automation("Safari")
      assert {:ok, status} = result
      assert status in [:granted, :not_granted]
    end

    @tag :integration
    test "checks Finder automation permission" do
      result = Permissions.check_automation("Finder")
      assert {:ok, status} = result
      assert status in [:granted, :not_granted]
    end

    @tag :integration
    test "checks Mail automation permission" do
      result = Permissions.check_automation("Mail")
      assert {:ok, status} = result
      assert status in [:granted, :not_granted]
    end

    @tag :integration
    test "checks Messages automation permission" do
      result = Permissions.check_automation("Messages")
      assert {:ok, status} = result
      assert status in [:granted, :not_granted]
    end
  end

  describe "open_accessibility_preferences/0" do
    @tag :integration
    @tag :skip
    test "opens accessibility preferences" do
      assert :ok = Permissions.open_accessibility_preferences()
      # System Settings should now be open
      Process.sleep(1000)
    end
  end

  describe "open_automation_preferences/0" do
    @tag :integration
    @tag :skip
    test "opens automation preferences" do
      assert :ok = Permissions.open_automation_preferences()
      # System Settings should now be open
      Process.sleep(1000)
    end
  end

  describe "check_all/0" do
    @tag :integration
    test "returns status map with all permissions" do
      statuses = Permissions.check_all()

      assert is_map(statuses)
      assert Map.has_key?(statuses, :accessibility)
      assert Map.has_key?(statuses, :safari_automation)
      assert Map.has_key?(statuses, :finder_automation)
      assert Map.has_key?(statuses, :mail_automation)
      assert Map.has_key?(statuses, :messages_automation)

      # All statuses should be valid
      Enum.each(statuses, fn {_perm, status} ->
        assert status in [:granted, :not_granted, :error]
      end)
    end

    @tag :integration
    test "result is consistent across multiple calls" do
      statuses1 = Permissions.check_all()
      statuses2 = Permissions.check_all()
      assert statuses1 == statuses2
    end
  end
end
