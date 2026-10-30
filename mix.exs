defmodule ExMacosControl.MixProject do
  use Mix.Project

  @source_url "https://github.com/houllette/ex_macos_control"
  @version "0.2.0"

  def project do
    [
      app: :ex_macos_control,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Elixir wrapper library for macOS interaction through osascript and Shortcuts",
      name: "ExMacOSControl",
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_local_path: "tmp/plts",
        plt_core_path: "tmp/plts",
        plt_add_apps: [:mix] ++ if(Mix.env() == :test, do: [:ex_unit], else: [])
      ],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :xmerl]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4", warn_if_outdated: true},
      {:telemetry, "~> 1.4", warn_if_outdated: true},
      {:tidewave, "~> 0.9.2", only: :dev, warn_if_outdated: true},
      {:bandit, "~> 1.14", only: :dev, warn_if_outdated: true},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false, warn_if_outdated: true},
      {:sbom, "~> 0.12.0", only: :dev, runtime: false, warn_if_outdated: true},
      {:mox, "~> 1.2", only: :test, warn_if_outdated: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:excoveralls, "~> 0.18", only: :test, warn_if_outdated: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Holden Oullette"],
      links: %{
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "docs/testing.md",
        "docs/git_hooks.md",
        "docs/guides/getting_started.md",
        "docs/guides/common_patterns.md",
        "docs/guides/dsl_vs_raw.md",
        "docs/guides/advanced_usage.md",
        "docs/performance.md",
        "docs/creating_app_modules.md"
      ],
      groups_for_extras: [
        Guides: ~r/docs\/guides\/.*/,
        Reference: ~r/docs\/(performance|creating_app_modules).*/
      ],
      groups_for_modules: [
        Compositions: [
          ExMacOSControl.Capture,
          ExMacOSControl.Capture.Page,
          ExMacOSControl.Capture.Text,
          ExMacOSControl.Capture.Files,
          ExMacOSControl.Capture.Message,
          ExMacOSControl.Capture.Event,
          ExMacOSControl.Composition,
          ExMacOSControl.Workflows,
          ExMacOSControl.Applications,
          ExMacOSControl.Desktop,
          ExMacOSControl.Safari.Page
        ],
        Core: [
          ExMacOSControl,
          ExMacOSControl.Adapter,
          ExMacOSControl.OSAScriptAdapter,
          ExMacOSControl.Error,
          ExMacOSControl.Platform,
          ExMacOSControl.Command,
          ExMacOSControl.Capabilities,
          ExMacOSControl.Shortcuts
        ],
        "Advanced Features": [
          ExMacOSControl.Script,
          ExMacOSControl.Retry,
          ExMacOSControl.Permissions,
          ExMacOSControl.Accessibility,
          ExMacOSControl.StandardAdditions,
          ExMacOSControl.PropertyList,
          ExMacOSControl.Qualification,
          ExMacOSControl.Wait
        ],
        "App Modules": [
          ExMacOSControl.SystemEvents,
          ExMacOSControl.Finder,
          ExMacOSControl.Safari,
          ExMacOSControl.Mail,
          ExMacOSControl.Messages,
          ExMacOSControl.Notes,
          ExMacOSControl.Calendar,
          ExMacOSControl.Reminders,
          ExMacOSControl.Contacts,
          ExMacOSControl.Photos,
          ExMacOSControl.Music,
          ExMacOSControl.TV,
          ExMacOSControl.QuickTime,
          ExMacOSControl.ImageEvents,
          ExMacOSControl.Terminal,
          ExMacOSControl.Automator,
          ExMacOSControl.SystemSettings,
          ExMacOSControl.FinalCutPro
        ]
      ]
    ]
  end

  defp aliases do
    [
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, ip: {127, 0, 0, 1}, port: 4000) end)'",
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "format.check": ["format --check-formatted"]
    ]
  end
end
