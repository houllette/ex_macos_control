defmodule ExMacosControl.MixProject do
  use Mix.Project

  @source_url "https://github.com/houllette/ex_macos_control"
  @version "0.1.1"

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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.3", warn_if_outdated: true},
      {:tidewave, "~> 0.5", only: :dev, warn_if_outdated: true},
      {:bandit, "~> 1.8", only: :dev, warn_if_outdated: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:sbom, "~> 0.6", only: :dev, runtime: false, warn_if_outdated: true},
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
        Core: [
          ExMacOSControl,
          ExMacOSControl.Adapter,
          ExMacOSControl.OSAScriptAdapter,
          ExMacOSControl.Error,
          ExMacOSControl.Platform
        ],
        "Advanced Features": [
          ExMacOSControl.Script,
          ExMacOSControl.Retry,
          ExMacOSControl.Permissions
        ],
        "App Modules": [
          ExMacOSControl.SystemEvents,
          ExMacOSControl.Finder,
          ExMacOSControl.Safari,
          ExMacOSControl.Mail,
          ExMacOSControl.Messages
        ]
      ]
    ]
  end

  defp aliases do
    [
      tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'",
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "format.check": ["format --check-formatted"]
    ]
  end
end
