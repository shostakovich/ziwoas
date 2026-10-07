defmodule Ziwoas.Solakon.PvHourAggregator do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.{LocalDay, Repo}
  alias Ziwoas.Solakon.{PvHour, Reading, Snapshot}

  @min_readings 20
  @panels [:pv1_power_w, :pv2_power_w, :pv3_power_w, :pv4_power_w]
  @no_panels Map.new(@panels, &{&1, nil})
  @seconds_per_hour 3600

  def min_readings, do: @min_readings

  defmacrop hour_start(taken_at, offset) do
    quote do
      fragment(
        "(CAST(strftime('%s', ?) AS INTEGER) + ?) / ? * ? - ?",
        unquote(taken_at),
        unquote(offset),
        @seconds_per_hour,
        @seconds_per_hour,
        unquote(offset)
      )
    end
  end

  @spec aggregate_day(String.t(), Date.t()) :: :ok
  def aggregate_day(zone, %Date{} = date) do
    day = LocalDay.midnight(date, zone)
    next_day = date |> Date.add(1) |> LocalDay.midnight(zone)
    # Also right for zones whose offset is not a whole hour (Asia/Kolkata).
    offset = day.utc_offset + day.std_offset
    panels = panel_means(day, next_day, offset)

    rows =
      for %{hour: epoch, pv_power_w: pv_power_w, count: count} <-
            reading_means(day, next_day, offset),
          count >= @min_readings do
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
    hours =
      from r in Reading,
        where: r.taken_at >= ^from and r.taken_at < ^to,
        select: %{hour: hour_start(r.taken_at, ^offset), pv_power_w: r.pv_power_w}

    Repo.all(
      from h in subquery(hours),
        group_by: h.hour,
        select: %{hour: h.hour, pv_power_w: avg(h.pv_power_w), count: count()}
    )
  end

  defp panel_means(from, to, offset) do
    hours =
      from s in Snapshot,
        where: s.taken_at >= ^from and s.taken_at < ^to,
        select: %{
          hour: hour_start(s.taken_at, ^offset),
          pv1_power_w: s.pv1_power_w,
          pv2_power_w: s.pv2_power_w,
          pv3_power_w: s.pv3_power_w,
          pv4_power_w: s.pv4_power_w
        }

    Repo.all(
      from h in subquery(hours),
        group_by: h.hour,
        select:
          {h.hour,
           %{
             pv1_power_w: avg(h.pv1_power_w),
             pv2_power_w: avg(h.pv2_power_w),
             pv3_power_w: avg(h.pv3_power_w),
             pv4_power_w: avg(h.pv4_power_w)
           }}
    )
    |> Map.new()
  end

  defp local_date(time, zone), do: time |> DateTime.shift_zone!(zone) |> DateTime.to_date()
end
