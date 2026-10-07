defmodule Ziwoas.SunCalendar do
  @moduledoc """
  A year of the PV plant hour by hour: PV power, irradiance and cloud cover as
  strips of day × local hour, the daily energy, and the lines of sunrise,
  sunset and solar noon. Before the inverter's PV hours begin (the seam), the
  producer plugs' five-minute energy stands in for the PV power.
  """

  alias Ziwoas.{LocalDay, Location, Plugs, Solakon, Weather}
  alias Ziwoas.SunCalendar.SunLines

  @base_hours {3, 22}
  @watts_per_kilowatt 1000.0
  @max_step 50

  def base_hours, do: @base_hours

  defmodule Strip do
    @moduledoc """
    One quantity over the year (`:pv` in W, `:irradiance` in W/m², `:cloud` in
    %): `values` is keyed by `{day of year, local clock hour}`, `max` is the top
    of its scale.
    """
    defstruct [:key, :max, :values]

    @type t :: %__MODULE__{key: :pv | :irradiance | :cloud, max: float, values: map}
  end

  defmodule Day do
    @moduledoc false
    defstruct [:doy, :date, :pv_kwh, :irradiance_kwh_per_m2, :cloud_avg]
  end

  defmodule Lines do
    @moduledoc "Points are `{day of year, local hour}`."
    defstruct [:rise, :set, :noon]

    def empty?(%__MODULE__{rise: rise}), do: rise == []
  end

  defmodule Year do
    @moduledoc "`strips` in drawing order: PV, irradiance, cloud cover."
    defstruct [:year, :days, :hours, :strips, :max_kwh, :lines, :seam]

    @type t :: %__MODULE__{}

    def empty?(%__MODULE__{strips: [pv | _]}), do: pv.values == %{}
  end

  @doc "The year of the newest PV hour, else the current one."
  @spec latest_year(Location.t(), DateTime.t()) :: integer
  def latest_year(%Location{timezone: zone}, now) do
    (Solakon.latest_pv_hour_start() || now)
    |> DateTime.shift_zone!(zone)
    |> Map.fetch!(:year)
  end

  @doc "One calendar year of the PV plant; `producer_ids` stand in before the seam."
  @spec year(Location.t(), [String.t()], integer) :: Year.t()
  def year(%Location{} = location, producer_ids, year) do
    zone = location.timezone
    range = {utc_midnight(year, zone), utc_midnight(year + 1, zone)}

    pv = pv_points(range, zone)
    seam = seam_date(pv)
    plug = plug_points(range, seam, producer_ids, zone)
    weather = Weather.historic_records(location, elem(range, 0), elem(range, 1))
    irradiance = weather_points(weather, zone, &Weather.solar_w_per_m2/1)
    cloud = weather_points(weather, zone, & &1.cloud_cover)

    strips = [
      strip(:pv, plug ++ pv),
      strip(:irradiance, irradiance),
      %Strip{key: :cloud, max: 100.0, values: cells(cloud)}
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
          kwh -> Enum.max(kwh)
        end,
      lines: lines,
      seam: if(plug != [], do: seam)
    }
  end

  defp utc_midnight(year, zone),
    do: Date.new!(year, 1, 1) |> LocalDay.midnight(zone) |> DateTime.shift_zone!("Etc/UTC")

  defp pv_points({from, to}, zone) do
    for hour <- Solakon.pv_hours_between(from, to),
        do: {DateTime.shift_zone!(hour.started_at, zone), hour.pv_power_w}
  end

  defp seam_date([{time, _} | _]), do: DateTime.to_date(time)
  defp seam_date([]), do: nil

  defp plug_points(_range, _seam, [], _zone), do: []

  defp plug_points({from, to}, seam, producer_ids, zone) do
    # Unordered: the running sums follow SQLite's row order.
    rows = Plugs.five_minute_energy(producer_ids, from, to)

    {order, totals} =
      Enum.reduce(rows, {[], %{}}, fn {bucket_ts, energy_wh}, acc ->
        time = LocalDay.local_time(bucket_ts, zone)

        if seam && Date.compare(DateTime.to_date(time), seam) != :lt,
          do: acc,
          else: add_to_hour(acc, time, energy_wh)
      end)

    order |> Enum.sort() |> Enum.map(&Map.fetch!(totals, &1))
  end

  defp add_to_hour({order, totals}, time, energy_wh) do
    hour = %{time | minute: 0, second: 0, microsecond: {0, 0}}
    key = DateTime.to_unix(hour)
    energy = (energy_wh || 0) * 1.0

    case totals do
      %{^key => {_, sum}} -> {order, %{totals | key => {hour, sum + energy}}}
      _ -> {[key | order], Map.put(totals, key, {hour, 0.0 + energy})}
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

  defp strip(key, points) do
    values = cells(points)
    %Strip{key: key, max: rounded_max(values), values: values}
  end

  defp rounded_max(values) do
    peak =
      if values == %{}, do: 0.0, else: values |> Map.values() |> Enum.max()

    :erlang.float(max(ceil(peak / @max_step) * @max_step, @max_step))
  end

  defp hour_range(strips, lines) do
    {base_first, base_last} = @base_hours
    hours = for strip <- strips, {_doy, hour} <- Map.keys(strip.values), do: hour
    events = lines.rise ++ lines.set

    {Enum.min([base_first | hours] ++ Enum.map(events, fn {_, hour} -> floor(hour) end)),
     Enum.max([base_last | hours] ++ Enum.map(events, fn {_, hour} -> ceil(hour) end))}
  end

  defp days(year, pv, solar, cloud) do
    kwh =
      pv
      |> by_day()
      |> Map.new(fn {doy, values} -> {doy, Enum.sum(values) / @watts_per_kilowatt} end)

    irradiance =
      solar |> by_day() |> Map.new(fn {doy, values} -> {doy, Enum.sum(values)} end)

    cloud_avg =
      cloud
      |> by_day()
      |> Map.new(fn {doy, values} -> {doy, Enum.sum(values) / length(values)} end)

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
end
