defmodule Ziwoas.Solakon.PvHourAggregator do
  @moduledoc """
  Condenses a finished local day of inverter readings into hourly PV means
  (`solakon_pv_hours`), with the four panel means from the snapshots of the same
  hour. Hours with fewer than 20 readings are dropped. The averages are taken in
  SQLite.
  """
  import Ecto.Query

  alias Ziwoas.{LocalDay, Repo}
  alias Ziwoas.Solakon.{PvHour, Reading}

  @min_readings 20
  @panels [:pv1_power_w, :pv2_power_w, :pv3_power_w, :pv4_power_w]
  @no_panels Map.new(@panels, &{&1, nil})

  def min_readings, do: @min_readings

  @doc "Rewrites the PV hours of one local day."
  @spec aggregate_day(String.t(), Date.t()) :: :ok
  def aggregate_day(zone, %Date{} = date) do
    day = LocalDay.midnight(date, zone)
    next_day = date |> Date.add(1) |> LocalDay.midnight(zone)
    {from, to} = {Repo.dump_time(day), Repo.dump_time(next_day)}
    # The day's offset at midnight shifts the buckets onto local hours, also in
    # zones like Asia/Kolkata whose offset is not a whole hour.
    offset = day.utc_offset + day.std_offset
    panels = panel_means(from, to, offset)

    rows =
      for [epoch, pv_power_w, count] <- reading_means(from, to, offset), count >= @min_readings do
        Map.merge(
          %{
            started_at: DateTime.from_unix!(epoch * 1_000_000, :microsecond),
            pv_power_w: pv_power_w,
            reading_count: count
          },
          Map.get(panels, epoch, @no_panels)
        )
      end

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.delete_all(
          from h in PvHour,
            where: h.started_at >= ^day and h.started_at < ^next_day
        )

        Repo.insert_all(PvHour, rows)
      end)

    :ok
  end

  @doc "Aggregates every finished local day since the first reading that has no PV hours yet."
  @spec run_once(String.t(), Date.t()) :: :ok
  def run_once(zone, %Date{} = today) do
    case Repo.one(from r in Reading, select: min(r.taken_at)) do
      nil ->
        :ok

      first ->
        filled =
          from(h in PvHour, select: h.started_at)
          |> Repo.all()
          |> MapSet.new(&local_date(&1, zone))

        for date <- Date.range(local_date(first, zone), Date.add(today, -1), 1),
            date not in filled,
            do: aggregate_day(zone, date)

        :ok
    end
  end

  defp reading_means(from, to, offset) do
    hour = hour_start_sql(offset)

    Repo.query!(
      "SELECT #{hour}, AVG(pv_power_w), COUNT(*) FROM solakon_readings " <>
        "WHERE taken_at >= ? AND taken_at < ? GROUP BY #{hour}",
      [from, to]
    ).rows
  end

  defp panel_means(from, to, offset) do
    hour = hour_start_sql(offset)
    means = Enum.map_join(@panels, ", ", &"AVG(#{&1})")

    Repo.query!(
      "SELECT #{hour}, #{means} FROM solakon_snapshots " <>
        "WHERE taken_at >= ? AND taken_at < ? GROUP BY #{hour}",
      [from, to]
    ).rows
    |> Map.new(fn [epoch | values] -> {epoch, Map.new(Enum.zip(@panels, values))} end)
  end

  # Epoch of the local clock hour a row falls into; the offset is an integer.
  defp hour_start_sql(offset) when is_integer(offset),
    do: "(CAST(strftime('%s', taken_at) AS INTEGER) + #{offset}) / 3600 * 3600 - #{offset}"

  defp local_date(time, zone), do: time |> DateTime.shift_zone!(zone) |> DateTime.to_date()
end
