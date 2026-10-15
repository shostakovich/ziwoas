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
      {:websock_adapter, "~> 0.6"},
      {:req, "~> 0.7.4"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:setzkasten, github: "shostakovich/setzkasten"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind ziwoas", "esbuild ziwoas"],
      "assets.deploy": [
        "compile",
        "tailwind ziwoas --minify",
        "esbuild ziwoas --minify",
        "phx.digest"
      ]
    ]
  end
end
