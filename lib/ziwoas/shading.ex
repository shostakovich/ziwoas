defmodule Ziwoas.Shading do
  @moduledoc false
  alias Ziwoas.{Location, Solakon, Sun, Weather}
  alias Ziwoas.Shading.{DailyProfiles, PanelCurves, SunPaths, YieldMap}

  @calibration_min_irradiance_w_per_m2 300
  # A percentile, not the maximum: one underreported irradiance hour would set the scale.
  @best_hour_percentile 0.95
  @middle_of_hour_s 30 * 60

  defmodule Hour do
    @moduledoc false
    @enforce_keys [:time, :pv_w, :irradiance_w_per_m2, :panels, :azimuth, :elevation]
    defstruct @enforce_keys

    def ratio(%__MODULE__{irradiance_w_per_m2: nil}), do: nil

    def ratio(%__MODULE__{pv_w: pv_w, irradiance_w_per_m2: irradiance}),
      do: if(irradiance == 0, do: nil, else: pv_w / irradiance)

    def date(%__MODULE__{time: time}), do: DateTime.to_date(time)
    def positioned?(%__MODULE__{elevation: elevation}), do: not is_nil(elevation)
  end

  defmodule Bin do
    @moduledoc false
    defstruct [:azimuth, :elevation, :share, :hours, :first_hour, :last_hour]
  end

  defmodule Dot do
    @moduledoc false
    defstruct [:hour, :azimuth, :elevation]
  end

  defmodule Path do
    @moduledoc false
    defstruct [:day, :points, :dots]
  end

  defmodule Curve do
    @moduledoc false
    defstruct [:key, :points]

    def empty?(%__MODULE__{points: points}), do: points == []

    def max(%__MODULE__{points: points}),
      do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()
  end

  defmodule Profile do
    @moduledoc false
    defstruct [:month, :days, :curves]
  end

  defmodule Panels do
    @moduledoc false
    defstruct [:curves, :days, :since]

    def empty?(%__MODULE__{curves: curves}), do: Enum.all?(curves, &Curve.empty?/1)
  end

  defmodule SkyMap do
    @moduledoc false
    defstruct [:bins, :paths, :bin_size]
  end

  defmodule Report do
    @moduledoc false
    defstruct [:map, :profiles, :panels]

    def empty?(%__MODULE__{map: map, profiles: profiles}), do: map.bins == [] and profiles == []
  end

  @doc "`now` picks the year whose sun paths stand in for every year of hours."
  @spec report(Location.t(), DateTime.t()) :: Report.t()
  def report(%Location{} = location, now) do
    hours = measured_hours(location)
    best_ratio = best_ratio(hours)
    year = now |> DateTime.shift_zone!(location.timezone) |> Map.fetch!(:year)

    %Report{
      map: YieldMap.build(hours, SunPaths.build(location, year), best_ratio),
      profiles: DailyProfiles.build(hours, best_ratio),
      panels: PanelCurves.build(hours)
    }
  end

  defp measured_hours(location) do
    rows = Solakon.pv_hours()
    irradiance = irradiance_by_time(location, rows)

    for row <- rows do
      position = Sun.position(location, DateTime.add(row.started_at, @middle_of_hour_s))

      %Hour{
        time: DateTime.shift_zone!(row.started_at, location.timezone),
        pv_w: row.pv_power_w,
        irradiance_w_per_m2: Map.get(irradiance, DateTime.to_unix(row.started_at)),
        panels: [row.pv1_power_w, row.pv2_power_w, row.pv3_power_w, row.pv4_power_w],
        azimuth: position && position.azimuth,
        elevation: position && position.elevation
      }
    end
  end

  # The station stamps a record with the end of its hour.
  defp irradiance_by_time(_location, []), do: %{}

  defp irradiance_by_time(location, rows) do
    from = DateTime.add(hd(rows).started_at, 3600)
    to = List.last(rows).started_at |> DateTime.add(3600) |> DateTime.add(1, :microsecond)

    location
    |> Weather.historic_records(from, to)
    |> Enum.reduce(%{}, &put_irradiance/2)
  end

  defp put_irradiance(record, out) do
    case Weather.solar_w_per_m2(record) do
      nil ->
        out

      value ->
        started_at = DateTime.add(record.timestamp, -Weather.period_minutes(record) * 60)
        Map.put(out, DateTime.to_unix(started_at), value)
    end
  end

  defp best_ratio(hours) do
    ratios =
      for hour <- hours,
          (hour.irradiance_w_per_m2 || 0.0) >= @calibration_min_irradiance_w_per_m2,
          ratio = Hour.ratio(hour),
          not is_nil(ratio),
          do: ratio

    case ratios do
      [] ->
        nil

      ratios ->
        best = Enum.at(Enum.sort(ratios), floor(length(ratios) * @best_hour_percentile))
        if best > 0, do: best
    end
  end

  def curve(%{curves: curves}, key), do: Enum.find(curves, &(&1.key == key))

  def hours(%{curves: curves}),
    do: Enum.flat_map(curves, fn curve -> Enum.map(curve.points, &elem(&1, 0)) end)

  def max(%{curves: curves}) do
    case curves |> Enum.reject(&Curve.empty?/1) |> Enum.map(&Curve.max/1) do
      [] -> nil
      maxima -> Enum.max(maxima)
    end
  end

  @doc "The inverter reports zeros through the night; dropping them lets the day fill the chart."
  def daylight(curves) do
    hours =
      for curve <- curves, {hour, value} <- curve.points, value != 0, do: hour

    if hours != [], do: Enum.min_max(hours)
  end

  def trim(curves) do
    window = daylight(curves)

    for curve <- curves, do: %Curve{key: curve.key, points: points_within(curve.points, window)}
  end

  defp points_within(_points, nil), do: []

  defp points_within(points, {first, last}),
    do: Enum.filter(points, fn {hour, _} -> hour >= first and hour <= last end)

  def group_by(items, fun) do
    {keys, groups} =
      Enum.reduce(items, {[], %{}}, fn item, {keys, groups} ->
        key = fun.(item)

        case groups do
          %{^key => group} -> {keys, %{groups | key => [item | group]}}
          _ -> {[key | keys], Map.put(groups, key, [item])}
        end
      end)

    keys |> Enum.reverse() |> Enum.map(&{&1, Enum.reverse(Map.fetch!(groups, &1))})
  end
end
