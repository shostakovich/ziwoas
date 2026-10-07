defmodule Ziwoas.Trmnl.SensorPayload do
  @moduledoc """
  The TRMNL sensor widget's `merge_variables` (Rails' `TrmnlSensorPayloadBuilder`):
  one entry per configured sensor, in config order, with a 3-hour trend in
  twelve 15-minute buckets. An ordered pair list for `Ziwoas.RubyJSON`.
  """
  alias Ziwoas.{Clock, Config, LocalDay, RubyNumeric, Sensors}
  alias Ziwoas.Config.Sensor
  alias Ziwoas.Sensors.ReadingPresenter

  @bucket_seconds 15 * 60
  @buckets 12

  @spec build(Config.t(), DateTime.t()) :: [{String.t(), term}]
  def build(%Config{} = config, now \\ Clock.now()) do
    zone = config.location.timezone
    entries = Enum.map(config.sensors, &entry(&1, now, zone))

    [{"merge_variables", [{"stand", stand(config.sensors, now, zone)}, {"sensors", entries}]}]
  end

  defp entry(%Sensor{} = sensor, now, zone) do
    outdoor = sensor.type == :outdoor_meter
    latest = Sensors.latest(sensor.id)
    offline = ReadingPresenter.offline?(latest, now)

    base = %{
      primary: nil,
      ampel: nil,
      trend: [],
      trend_min: nil,
      trend_max: nil,
      temperature: nil,
      humidity: nil
    }

    values =
      if offline, do: base, else: Map.merge(base, readings(sensor, latest, now, zone, outdoor))

    [
      {"id", sensor.id},
      {"name", sensor.name},
      {"type", if(outdoor, do: "outdoor", else: "indoor")},
      {"primary", values.primary},
      {"unit", if(outdoor, do: "°C", else: "ppm CO₂")},
      {"ampel", values.ampel},
      {"trend", values.trend},
      {"trend_min", values.trend_min},
      {"trend_max", values.trend_max},
      {"temperature", values.temperature},
      {"humidity", values.humidity},
      {"battery_low", ReadingPresenter.battery_low?(latest)},
      {"battery_pct", latest && latest.battery_pct},
      {"age_label", ReadingPresenter.age_label(latest, now)},
      {"offline", offline}
    ]
  end

  defp readings(sensor, latest, now, zone, outdoor) do
    temperature = RubyNumeric.round(RubyNumeric.to_f(latest.temperature), 1)
    trend = trend(sensor, now, zone, outdoor)
    present = Enum.reject(trend, &is_nil/1)

    %{
      primary: if(outdoor, do: temperature, else: RubyNumeric.to_i(latest.co2)),
      ampel: if(outdoor, do: nil, else: co2_level(latest)),
      temperature: temperature,
      humidity: latest.humidity,
      trend: trend,
      trend_min: if(present == [], do: nil, else: RubyNumeric.min(present)),
      trend_max: if(present == [], do: nil, else: RubyNumeric.max(present))
    }
  end

  defp co2_level(latest) do
    case ReadingPresenter.co2_level(latest) do
      nil -> nil
      level -> Atom.to_string(level)
    end
  end

  defp trend(sensor, now, zone, outdoor) do
    {start_ts, end_ts} = window(now, zone)
    column = if outdoor, do: :temperature, else: :co2

    by_bucket =
      sensor.id
      |> Sensors.values_between(
        column,
        DateTime.from_unix!(start_ts),
        DateTime.from_unix!(end_ts)
      )
      |> Enum.reject(fn {_taken_at, value} -> is_nil(value) end)
      |> Enum.group_by(
        fn {taken_at, _value} ->
          Integer.floor_div(DateTime.to_unix(taken_at) - start_ts, @bucket_seconds)
        end,
        fn {_taken_at, value} -> value end
      )

    for idx <- 0..(@buckets - 1) do
      case Map.get(by_bucket, idx) do
        nil -> nil
        values -> average(values, outdoor)
      end
    end
  end

  defp average(values, outdoor) do
    avg = RubyNumeric.to_f(RubyNumeric.sum(values)) / length(values)
    if outdoor, do: RubyNumeric.round(avg, 1), else: RubyNumeric.round(avg, 0)
  end

  @doc "`{start_ts, end_ts}`: 3 hours up to the 15-minute boundary after `now`, local time."
  @spec window(DateTime.t(), String.t()) :: {integer, integer}
  def window(now, zone) do
    local = DateTime.shift_zone!(now, zone)

    slot = %{
      DateTime.to_naive(local)
      | minute: div(local.minute, 15) * 15,
        second: 0,
        microsecond: {0, 0}
    }

    end_ts = DateTime.to_unix(LocalDay.to_instant(slot, zone)) + @bucket_seconds
    {end_ts - @buckets * @bucket_seconds, end_ts}
  end

  defp stand(sensors, now, zone) do
    sensors
    |> Enum.map(&Sensors.latest_taken_at(&1.id))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> now
      times -> Enum.max(times, DateTime)
    end
    |> DateTime.shift_zone!(zone)
    |> Calendar.strftime("%H:%M")
  end
end
