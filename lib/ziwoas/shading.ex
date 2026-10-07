defmodule Ziwoas.Shading do
  @moduledoc """
  How much of the sun the panels turn into power, hour by hour: the PV hours against the station's irradiance and the sun's
  position. `Ziwoas.Shading.Builder` assembles the report the PV page shows.
  """
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
    defstruct [:label, :points, :dots]
  end

  defmodule Curve do
    @moduledoc "Points are `{hour, watts}`; an unmeasured hour is absent, not zero."
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

  @doc "The curve with `key` of a profile or the panels."
  def curve(%{curves: curves}, key), do: Enum.find(curves, &(&1.key == key))

  @doc "Every hour any curve has a point for, in curve order."
  def hours(%{curves: curves}),
    do: Enum.flat_map(curves, fn curve -> Enum.map(curve.points, &elem(&1, 0)) end)

  @doc "The highest point of the non-empty curves, or nil."
  def max(%{curves: curves}) do
    case curves |> Enum.reject(&Curve.empty?/1) |> Enum.map(&Curve.max/1) do
      [] -> nil
      maxima -> Enum.max(maxima)
    end
  end

  @doc """
  The inverter reports through the night as well; keeping those zeros would
  squeeze the day into the middle of the picture.
  """
  def daylight(curves) do
    hours =
      for curve <- curves, {hour, value} <- curve.points, value != 0, do: hour

    if hours != [], do: Enum.min_max(hours)
  end

  def trim(curves) do
    window = daylight(curves)

    for curve <- curves do
      points =
        case window do
          nil ->
            []

          {first, last} ->
            Enum.filter(curve.points, fn {hour, _} -> hour >= first and hour <= last end)
        end

      %Curve{key: curve.key, points: points}
    end
  end

  @doc "Groups in the order their keys first appear, as `[{key, items}]`."
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
