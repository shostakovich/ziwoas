defmodule Ziwoas.TestConfigs do
  @moduledoc false
  alias Ziwoas.Config

  @fixtures Path.expand("../fixtures", __DIR__)

  @base """
  location:
    timezone: Europe/Berlin
  """

  def file(:test), do: Path.join(@fixtures, "ziwoas.test.yml")
  def file(:inverter), do: Path.join(@fixtures, "ziwoas.inverter.yml")

  def load(name) do
    {:ok, config} = Config.load(file(name))
    config
  end

  def put(%Config{} = config), do: put({:ok, config})

  def put(result) do
    previous = Config.fetch()
    Config.put(result)
    ExUnit.Callbacks.on_exit(fn -> Config.put(previous) end)
  end

  def located(extra \\ "") do
    @base
    |> String.replace(
      "timezone: Europe/Berlin\n",
      "timezone: Europe/Berlin\n  lat: 52.52\n  lon: 13.405\n"
    )
    |> plugs_yaml(extra)
    |> Config.from_yaml!()
  end

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
