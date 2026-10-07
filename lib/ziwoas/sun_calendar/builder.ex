defmodule Ziwoas.SunCalendar.Builder do
  @moduledoc """
  One calendar year of the PV plant (Rails' `SunCalendar::Builder`). Before
  the inverter's PV hours begin (the seam), the producer plugs' five-minute
  energy stands in for the PV power.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, Location, Repo, RubyNumeric, Weather}
  alias Ziwoas.Solakon.PvHour
  alias Ziwoas.SunCalendar
  alias Ziwoas.SunCalendar.{Day, Strip, SunLines, Year}
  alias Ziwoas.Weather.Record

  @watts_per_kilowatt 1000.0
  @max_step 50

  @doc "The year of the newest PV hour, else the current one."
  @spec latest_year(Location.t(), DateTime.t()) :: integer
  def latest_year(%Location{timezone: zone}, now) do
    latest = Repo.one(from h in PvHour, select: max(h.started_at))
    (latest || now) |> to_datetime() |> DateTime.shift_zone!(zone) |> Map.fetch!(:year)
  end

  @spec build(Location.t(), [String.t()], integer) :: Year.t()
  def build(%Location{} = location, producer_ids, year) do
    zone = location.timezone

    range = {utc_midnight(year, zone), utc_midnight(year + 1, zone)}

    pv = pv_points(range, zone)
    seam = seam_date(pv)
    plug = plug_points(range, seam, producer_ids, zone)
    weather = weather_records(location, range)
    irradiance = weather_points(weather, zone, &Weather.solar_w_per_m2/1)
    cloud = weather_points(weather, zone, & &1.cloud_cover)

    strips = [
      strip(:pv, "PV-Leistung", "W", :amber, plug ++ pv),
      strip(:irradiance, "Einstrahlung", "W/m²", :blue, irradiance),
      %Strip{
        key: :cloud,
        title: "Bewölkung",
        unit: "%",
        ramp: :grey,
        max: 100.0,
        values: cells(cloud)
      }
    ]

    days = days(year, plug ++ pv, weather_points(weather, zone, & &1.solar), cloud)
    lines = SunLines.build(location, year)

    %Year{
      year: year,
      days: days,
      hours: hour_range(strips, lines),
      strips: strips,
      max_kwh:
        case Enum.reject(Enum.map(days, & &1.pv_kwh), &is_nil/1) do
          [] -> nil
          kwh -> RubyNumeric.max(kwh)
        end,
      lines: lines,
      seam: if(plug != [], do: seam)
    }
  end

  defp utc_midnight(year, zone),
    do: Date.new!(year, 1, 1) |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")

  defp pv_points({from, to}, zone) do
    Repo.all(
      from h in PvHour,
        where:
          h.started_at >= type(^from, Ziwoas.Ecto.RailsDateTime) and
            h.started_at < type(^to, Ziwoas.Ecto.RailsDateTime),
        order_by: h.started_at,
        select: {h.started_at, h.pv_power_w}
    )
    |> Enum.map(fn {time, watts} -> {DateTime.shift_zone!(time, zone), watts} end)
  end

  defp seam_date([{time, _} | _]), do: DateTime.to_date(time)
  defp seam_date([]), do: nil

  defp plug_points(_range, _seam, [], _zone), do: []

  defp plug_points({from, to}, seam, producer_ids, zone) do
    from_ts = DateTime.to_unix(from)
    to_ts = DateTime.to_unix(to)

    # Unordered, like Rails' pluck: the naive running sums follow SQLite's row order.
    %{rows: rows} =
      Repo.query!(
        "SELECT bucket_ts, energy_delta_wh FROM samples_5min WHERE plug_id IN (#{marks(producer_ids)}) " <>
          "AND bucket_ts >= ? AND bucket_ts < ?",
        producer_ids ++ [from_ts, to_ts]
      )

    {order, totals} =
      Enum.reduce(rows, {[], %{}}, fn [bucket_ts, energy_wh], {order, totals} = acc ->
        time = LocalDay.local_time(bucket_ts, zone)

        if seam && Date.compare(DateTime.to_date(time), seam) != :lt do
          acc
        else
          hour = beginning_of_hour(time)
          key = DateTime.to_unix(hour)
          energy = RubyNumeric.to_f(energy_wh)

          case totals do
            %{^key => {_, sum}} -> {order, %{totals | key => {hour, sum + energy}}}
            _ -> {[key | order], Map.put(totals, key, {hour, 0.0 + energy})}
          end
        end
      end)

    order |> Enum.sort() |> Enum.map(&Map.fetch!(totals, &1))
  end

  defp beginning_of_hour(%DateTime{} = time),
    do: %{time | minute: 0, second: 0, microsecond: {0, 0}}

  defp weather_records(location, {from, to}) do
    if Location.located?(location) do
      Repo.all(
        from r in Record,
          where:
            r.kind == "historic" and r.lat == ^location.lat and r.lon == ^location.lon and
              r.timestamp >= type(^from, Ziwoas.Ecto.RailsDateTime) and
              r.timestamp < type(^to, Ziwoas.Ecto.RailsDateTime),
          order_by: r.timestamp
      )
    else
      []
    end
  end

  defp weather_points(records, zone, value) do
    for record <- records,
        v = value.(record),
        not is_nil(v),
        do: {DateTime.shift_zone!(record.timestamp, zone), v}
  end

  # One cell per local clock hour. The autumn clock change repeats an hour;
  # its second reading wins the cell, while the day's totals keep both.
  defp cells(points),
    do: Map.new(points, fn {time, value} -> {{yday(time), time.hour}, value} end)

  defp strip(key, title, unit, ramp, points) do
    values = cells(points)

    %Strip{
      key: key,
      title: title,
      unit: unit,
      ramp: ramp,
      max: rounded_max(values),
      values: values
    }
  end

  defp rounded_max(values) do
    peak =
      if values == %{}, do: 0.0, else: values |> Map.values() |> Enum.max() |> RubyNumeric.to_f()

    :erlang.float(max(ceil(peak / @max_step) * @max_step, @max_step))
  end

  defp hour_range(strips, lines) do
    {base_first, base_last} = SunCalendar.base_hours()
    hours = for strip <- strips, {_doy, hour} <- Map.keys(strip.values), do: hour
    events = lines.rise ++ lines.set

    {Enum.min([base_first | hours] ++ Enum.map(events, fn {_, hour} -> floor(hour) end)),
     Enum.max([base_last | hours] ++ Enum.map(events, fn {_, hour} -> ceil(hour) end))}
  end

  defp days(year, pv, solar, cloud) do
    kwh =
      pv
      |> by_day()
      |> Map.new(fn {doy, values} -> {doy, RubyNumeric.sum(values) / @watts_per_kilowatt} end)

    irradiance =
      solar |> by_day() |> Map.new(fn {doy, values} -> {doy, RubyNumeric.sum(values)} end)

    cloud_avg =
      cloud
      |> by_day()
      |> Map.new(fn {doy, values} -> {doy, RubyNumeric.sum(values) / length(values)} end)

    for date <- Date.range(Date.new!(year, 1, 1), Date.new!(year, 12, 31)) do
      doy = Date.day_of_year(date)

      %Day{
        doy: doy,
        date: date,
        pv_kwh: kwh[doy],
        irradiance_kwh_per_m2: irradiance[doy],
        cloud_avg: cloud_avg[doy]
      }
    end
  end

  defp by_day(points) do
    points
    |> Enum.reduce(%{}, fn {time, value}, out ->
      Map.update(out, yday(time), [value], &[value | &1])
    end)
    |> Map.new(fn {doy, values} -> {doy, Enum.reverse(values)} end)
  end

  defp yday(time), do: time |> DateTime.to_date() |> Date.day_of_year()

  defp marks(ids), do: Enum.map_join(ids, ", ", fn _ -> "?" end)

  defp to_datetime(%DateTime{} = time), do: time
end
