defmodule Ziwoas.TestConfigs do
  @moduledoc "Device configs for tests: built from YAML here, or the files in test/fixtures."
  alias Ziwoas.Config

  @fixtures Path.expand("../fixtures", __DIR__)

  @base """
  location:
    timezone: Europe/Berlin
  """

  @doc """
  The path of a config file in test/fixtures: `:test` (the default under
  `MIX_ENV=test`) or `:inverter` (the same plus a Solakon inverter with
  monitoring and control enabled).
  """
  def file(:test), do: Path.join(@fixtures, "ziwoas.test.yml")
  def file(:inverter), do: Path.join(@fixtures, "ziwoas.inverter.yml")

  @doc "The config in test/fixtures named by `file/1`."
  def load(name) do
    {:ok, config} = Config.load(file(name))
    config
  end

  @doc """
  Makes `config` — a `%Ziwoas.Config{}`, `{:ok, config}` or `{:error, message}` —
  the one `Ziwoas.Config.fetch/0` and `get/0` answer, until the test ends. The
  config is VM-wide, so a test module that calls this cannot run async.
  """
  def put(%Config{} = config), do: put({:ok, config})

  def put(result) do
    previous = Config.fetch()
    Config.put(result)
    ExUnit.Callbacks.on_exit(fn -> Config.put(previous) end)
  end

  @doc "`plugs/1` with coordinates (Berlin's centre), as the weather jobs need them."
  def located(extra \\ "") do
    @base
    |> String.replace(
      "timezone: Europe/Berlin\n",
      "timezone: Europe/Berlin\n  lat: 52.52\n  lon: 13.405\n"
    )
    |> plugs_yaml(extra)
    |> Config.from_yaml!()
  end

  @doc "bkw (producer) and fridge (consumer) in Berlin, plus `extra` YAML."
  def plugs(extra \\ ""), do: @base |> plugs_yaml(extra) |> Config.from_yaml!()

  defp plugs_yaml(base, extra) do
    base <>
      """
      plugs:
        - id: bkw
          name: BKW
          role: producer
        - id: fridge
          name: Fridge
          role: consumer
      """ <> extra
  end
end
