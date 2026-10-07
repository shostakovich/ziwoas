defmodule Ziwoas.MixProject do
  use Mix.Project

  def project do
    [
      app: :ziwoas,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [ziwoas: [include_executables_for: [:unix]]],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {Ziwoas.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto, :xmerl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Kept deliberately small: no telemetry dashboard, no mailer. esbuild runs as a
  # standalone binary (no Node). JSON comes from Elixir's built-in JSON module. tz is the
  # IANA database for local day windows; Elixir itself only knows UTC. yamerl reads
  # config/ziwoas.yml (pure Erlang, no further deps). req is the outbound HTTP (Bright
  # Sky, SwitchBot, TRMNL, Fritz!Box, Govee Platform API) with Req.Test stubs.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.22"},
      {:bandit, "~> 1.5"},
      {:tz, "~> 0.28"},
      {:yamerl, "~> 0.10.0"},
      # The Shelly plugs' outbound websockets (Ziwoas.Shelly.Listener); Phoenix brings it.
      {:websock_adapter, "~> 0.6"},
      {:req, "~> 0.7.4"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Phoenix.LiveViewTest's HTML parser; tests only.
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild ziwoas", "esbuild ziwoas_css"],
      "assets.deploy": ["esbuild ziwoas --minify", "esbuild ziwoas_css --minify", "phx.digest"]
    ]
  end
end
