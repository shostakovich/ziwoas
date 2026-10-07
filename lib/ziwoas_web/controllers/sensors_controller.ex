defmodule ZiwoasWeb.SensorsController do
  @moduledoc """
  `/sensors/series` (Rails' `SensorsController#series`): the last 24 hours of
  every configured sensor as chart points, byte-identical through
  `Ziwoas.RubyJSON`. Like Rails' `render json:`, it answers whatever the
  request accepts. The page itself is `ZiwoasWeb.SensorsLive`.
  """
  use ZiwoasWeb, :controller

  alias Ziwoas.{Clock, Config, RubyJSON, Sensors}

  @window_seconds 24 * 3600

  def series(conn, _params) do
    sensors = Config.app_config().sensors
    since = DateTime.add(Clock.now(), -@window_seconds, :second)

    grouped =
      sensors |> Enum.map(& &1.id) |> Sensors.since(since) |> Enum.group_by(& &1.device_id)

    co2_sensors = Enum.filter(sensors, &(&1.type == :meter_pro_co2))

    payload = [
      {"temperature", series(grouped, sensors, :temperature)},
      {"humidity", series(grouped, sensors, :humidity)},
      {"co2", series(grouped, co2_sensors, :co2)}
    ]

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, RubyJSON.encode!(payload))
  end

  defp series(grouped, sensors, field) do
    for sensor <- sensors do
      points =
        for reading <- Map.get(grouped, sensor.id, []),
            value = Map.fetch!(reading, field),
            not is_nil(value),
            do: [DateTime.to_unix(reading.taken_at) * 1000, value]

      [{"device_id", sensor.id}, {"name", sensor.name}, {"points", points}]
    end
  end
end
