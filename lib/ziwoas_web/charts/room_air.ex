defmodule ZiwoasWeb.Charts.RoomAir do
  @moduledoc """
  The `RoomAirChart` hook's data: a room's series as `[ms, value | nil, 1 | 0]`, the last
  element marking a stand-in value; `nil` starts a gap. Values from one source are averaged
  into 5-minute buckets (15 for temperature and humidity), so the SEN66's minute-by-minute
  noise doesn't fray the lines; a gap or a change of source always starts a new point. A full
  payload (`replace: true`) also carries each chart's setup. An appended one recomputes the
  quarter hour the previous push ended in, so its buckets come out as a full payload's would:
  the client replaces its points from `from` on.
  """
  alias Ziwoas.{Config, Sensors}
  alias ZiwoasWeb.{Format, RoomAirComponents}

  @charted [:co2, :pm2_5, :pm10, :voc_index, :nox_index, :temperature, :humidity]
  @bucket_ms 300_000
  # Temperature and humidity drift slowly and come in 0.1 steps: a longer mean keeps them
  # from stairs.
  @slow_bucket_ms 900_000
  @slow [:temperature, :humidity]
  @verdict_lines %{warn: "Bald lüften", bad: "Jetzt lüften"}
  # Room above CO₂'s top line for its label on a phone's 500-step axis.
  @co2_axis_top 1500
  @temperature_span_k 3

  @spec replace(Config.t(), map, DateTime.t(), DateTime.t()) :: map
  def replace(%Config{} = config, room, from, to) do
    config
    |> payload(room, from, to)
    |> Map.merge(%{
      replace: true,
      charts: charts(room.quantities),
      stand_in: "Ersatzsensor, nicht abgeglichen",
      now_stand_in: "jetzt Ersatzsensor"
    })
  end

  @spec append(Config.t(), map, DateTime.t(), DateTime.t()) :: map
  def append(%Config{} = config, room, charted_to, to) do
    from_ms = floor_ms(DateTime.to_unix(charted_to, :millisecond), @slow_bucket_ms)
    # Starting a moment earlier, a point at `from` is kept or dropped as a full payload would.
    start = DateTime.add(DateTime.from_unix!(from_ms, :millisecond), -1, :second)

    config
    |> payload(room, start, to, &(&1 >= from_ms))
    |> Map.merge(%{replace: false, from: from_ms})
  end

  defp payload(config, room, from, to, keep? \\ fn _ms -> true end) do
    series = Sensors.room_series(config, room.name, from, to)

    %{
      room: room.id,
      to: DateTime.to_unix(to, :millisecond),
      series:
        for quantity <- @charted, quantity in room.quantities, into: %{} do
          points =
            series[quantity]
            |> Enum.map(&point/1)
            |> Enum.filter(fn [ms | _] -> keep?.(ms) end)

          {quantity, smooth(points, bucket_ms(quantity))}
        end
    }
  end

  defp floor_ms(ms, bucket_ms), do: Integer.floor_div(ms, bucket_ms) * bucket_ms

  defp point(%{at: at, value: value, source: source}),
    do: [DateTime.to_unix(at, :millisecond), value, if(source == :stand_in, do: 1, else: 0)]

  @doc """
  Averages runs of one source within a bucket (5 minutes by default); gaps and source
  changes stay points. Buckets are aligned to the epoch, so no run crosses a quarter hour.
  """
  @spec smooth([[number | nil]], pos_integer) :: [[number | nil]]
  def smooth(points, bucket_ms \\ @bucket_ms) do
    {runs, run} =
      Enum.reduce(points, {[], []}, fn
        [_at, nil, _source] = gap, {runs, run} ->
          {[gap | flush(run, runs)], []}

        [at, _value, source] = point, {runs, [[first, _, source] | _] = run}
        when div(at, bucket_ms) == div(first, bucket_ms) ->
          {runs, run ++ [point]}

        point, {runs, run} ->
          {flush(run, runs), [point]}
      end)

    run |> flush(runs) |> Enum.reverse()
  end

  defp bucket_ms(quantity) when quantity in @slow, do: @slow_bucket_ms
  defp bucket_ms(_quantity), do: @bucket_ms

  defp flush([], runs), do: runs

  defp flush([[at, _, source] | _] = run, runs) do
    values = Enum.map(run, &Enum.at(&1, 1))
    mean = Enum.sum(values) / length(values)

    [
      [
        at,
        if(Enum.all?(values, &is_integer/1), do: round(mean), else: Float.round(mean, 2)),
        source
      ]
      | runs
    ]
  end

  @spec charts([atom]) :: [map]
  def charts(quantities) do
    [
      chart(:co2, [:co2], lines: lines(:co2, [:warn, :bad]), suggested_max: @co2_axis_top),
      chart(:pm, [:pm2_5, :pm10], lines: lines(:pm2_5, [:warn, :bad])),
      chart(:voc_index, [:voc_index], lines: lines(:voc_index, [:warn, :bad])),
      chart(:nox_index, [:nox_index], lines: lines(:nox_index, [:warn])),
      chart(:temperature, [:temperature], from_zero: false, min_span: @temperature_span_k),
      chart(:humidity, [:humidity],
        from_zero: false,
        suggested_min: 20,
        suggested_max: 80,
        band: humidity_band()
      )
    ]
    |> Enum.filter(fn chart -> Enum.all?(chart.series, &(&1.quantity in quantities)) end)
  end

  defp chart(key, quantities, opts) do
    first = hd(quantities)

    %{
      key: key,
      unit: RoomAirComponents.unit(first) || "",
      decimals: RoomAirComponents.precision(first),
      series: Enum.map(quantities, &%{quantity: &1, label: RoomAirComponents.label(&1)}),
      lines: Keyword.get(opts, :lines, []),
      band: Keyword.get(opts, :band),
      from_zero: Keyword.get(opts, :from_zero, true),
      suggested_min: Keyword.get(opts, :suggested_min),
      suggested_max: Keyword.get(opts, :suggested_max),
      min_span: Keyword.get(opts, :min_span)
    }
  end

  # The first limit is where the level turns to warn, the next where it turns bad.
  defp lines(quantity, levels) do
    quantity
    |> Sensors.level_limits()
    |> Enum.zip(levels)
    |> Enum.map(fn {value, level} ->
      %{value: value, label: "#{Format.number(value)} #{@verdict_lines[level]}", level: level}
    end)
  end

  defp humidity_band do
    [_bad, low, high, _warn] = Sensors.level_limits(:humidity)
    [low, high]
  end
end
