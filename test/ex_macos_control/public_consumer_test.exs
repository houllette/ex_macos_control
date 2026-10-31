defmodule ExMacOSControl.PublicConsumerTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000

  test "public APIs work from an external project through both a path dependency and a built package" do
    root = File.cwd!()
    workspace = Path.join(root, "tmp/consumer-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(workspace) end)
    package = Path.join(workspace, "package")

    {output, status} =
      System.cmd("mix", ["hex.build", "--unpack", "--output", package],
        cd: root,
        stderr_to_stdout: true,
        env: [{"TMPDIR", Path.join(root, "tmp")}]
      )

    assert status == 0, output

    for {label, dependency} <- [{"path", root}, {"package", package}] do
      consumer = Path.join(workspace, "consumer-" <> label)
      File.mkdir_p!(Path.join(consumer, "tmp"))
      File.write!(Path.join(consumer, "mix.exs"), project(dependency))
      File.cp!("test/support/fixtures/consumer/probe.exs", Path.join(consumer, "probe.exs"))

      {output, status} =
        System.cmd("mix", ["run", "probe.exs"],
          cd: consumer,
          stderr_to_stdout: true,
          env: [
            {"MIX_ENV", "prod"},
            {"MIX_BUILD_PATH", Path.join(consumer, "build")},
            {"MIX_DEPS_PATH", Path.join(consumer, "deps")},
            {"TMPDIR", Path.join(consumer, "tmp")}
          ]
        )

      File.write!(Path.join(workspace, label <> ".log"), output)
      assert status == 0, output
      assert output =~ ~s("status":"passed")
      assert output =~ ~s("reads":2)
      assert output =~ ~s("writes":2)
    end
  end

  defp project(dependency) do
    jason = Mix.Project.deps_paths()[:jason]
    telemetry = Mix.Project.deps_paths()[:telemetry]

    """
    defmodule Consumer.MixProject do
      use Mix.Project
      def project, do: [app: :consumer_probe, version: "0.0.0", deps: deps()]
      def application, do: [extra_applications: [:logger]]
      defp deps, do: [
        {:ex_macos_control, path: #{inspect(dependency)}},
        {:jason, path: #{inspect(jason)}, override: true},
        {:telemetry, path: #{inspect(telemetry)}, override: true}
      ]
    end
    """
  end
end
