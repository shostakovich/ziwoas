defmodule Ziwoas.Trmnl.PreviewVariablesTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Repo, TestConfigs}
  alias Ziwoas.Sensors.Reading
  alias Ziwoas.Trmnl.{EnergyPayload, SensorPayload}

  @now ~U[2026-05-12 14:56:00.000000Z]
  @trmnl Path.expand("../../../trmnl", __DIR__)

  test "the energy plugin's preview variables have the payload's keys" do
    payload = merge_variables(EnergyPayload.build(TestConfigs.plugs(), @now))

    assert keys(variables("energy/.trmnlp.yml")) == keys(payload)
  end

  describe "the sensor plugin's preview variables" do
    setup do
      config =
        TestConfigs.plugs("""
        sensors:
          - { id: SEN, name: Raumluft, type: sen66, room: Wohnzimmer, port: /dev/x }
          - { id: METER, name: Wohnzimmer, type: meter_pro_co2, room: Wohnzimmer }
          - { id: OUTDOOR, name: Balkon, type: outdoor_meter }
        """)

      insert!("SEN", 20, %{
        co2: 780,
        pm2_5: 6.2,
        pm10: 8.5,
        voc_index: 118,
        nox_index: 2,
        temperature: 26.5,
        humidity: 62.0
      })

      insert!("METER", 60, %{co2: 815, temperature: 26.4, humidity: 61.0})
      insert!("OUTDOOR", 60, %{temperature: 21.0, humidity: 70.0})

      %{payload: merge_variables(SensorPayload.build(config, @now))}
    end

    test "the payload is rich: every nested map is there", %{payload: payload} do
      assert Enum.all?(~w[values levels balcony], &is_map(payload[&1]))
    end

    test "have the payload's keys", %{payload: payload} do
      preview = variables("sensors/.trmnlp.yml")

      assert keys(preview) == keys(payload)

      for {key, value} <- preview, is_map(value) or is_map(payload[key]) do
        assert value == nil or keys(value) == keys(payload[key]), "#{key} differs"
      end
    end
  end

  defp insert!(device_id, seconds_ago, measurements) do
    taken_at = DateTime.add(@now, -seconds_ago, :second)
    Repo.insert!(struct!(%Reading{device_id: device_id, taken_at: taken_at}, measurements))
  end

  defp merge_variables(built),
    do: built |> JSON.encode!() |> JSON.decode!() |> Map.fetch!("merge_variables")

  defp variables(path) do
    full = Path.join(@trmnl, path)
    [document] = :yamerl_constr.file(String.to_charlist(full), [:str_node_as_binary])
    document |> to_map() |> Map.fetch!("variables")
  end

  defp to_map([{key, _value} | _] = pairs) when is_binary(key),
    do: Map.new(pairs, fn {key, value} -> {key, to_map(value)} end)

  defp to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_map(:null), do: nil
  defp to_map(value), do: value

  defp keys(map), do: map |> Map.keys() |> Enum.sort()
end
