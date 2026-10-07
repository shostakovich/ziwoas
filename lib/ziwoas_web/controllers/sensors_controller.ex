defmodule ZiwoasWeb.SensorsController do
  @moduledoc """
  `/sensors/series`: the last 24 hours of every configured sensor as chart points
  (`[unix_ms, value]`), read by the `SensorsChart` hook. The page itself is
  `ZiwoasWeb.SensorsLive`.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config, Sensors}

  @window_seconds 24 * 3600

  def series(conn, _params) do
    sensors = Config.app_config().sensors
    since = DateTime.add(Clock.now(), -@window_seconds, :second)

    grouped =
      sensors |> Enum.map(& &1.id) |> Sensors.since(since) |> Enum.group_by(& &1.device_id)

    co2_sensors = Enum.filter(sensors, &(&1.type == :meter_pro_co2))

    json(conn, %{
      temperature: series(grouped, sensors, :temperature),
      humidity: series(grouped, sensors, :humidity),
      co2: series(grouped, co2_sensors, :co2)
    })
  end

  defp series(grouped, sensors, field) do
    for sensor <- sensors do
      points =
        for reading <- Map.get(grouped, sensor.id, []),
            value = Map.fetch!(reading, field),
            not is_nil(value),
            do: [DateTime.to_unix(reading.taken_at, :millisecond), value]

      %{device_id: sensor.id, name: sensor.name, points: points}
    end
  end
end
