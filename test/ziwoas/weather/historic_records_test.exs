defmodule Ziwoas.Weather.HistoricRecordsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Location, Repo, Weather}
  alias Ziwoas.Weather.Record

  @berlin Location.new("Europe/Berlin", lat: 52.52, lon: 13.405)

  defp record!(kind, timestamp, lat \\ 52.52) do
    Repo.insert!(%Record{
      kind: kind,
      lat: lat,
      lon: 13.405,
      timestamp: usec(timestamp),
      daytime: "day"
    })
  end

  test "the location's historic records in [from, to), oldest first" do
    record!("historic", ~U[2026-05-04 12:00:00Z])
    record!("historic", ~U[2026-05-04 10:00:00Z])
    record!("historic", ~U[2026-05-04 11:00:00Z])
    record!("historic", ~U[2026-05-04 09:00:00Z])
    record!("forecast", ~U[2026-05-04 10:00:00Z])
    record!("historic", ~U[2026-05-04 10:00:00Z], 48.1)

    records =
      Weather.historic_records(@berlin, ~U[2026-05-04 10:00:00Z], ~U[2026-05-04 12:00:00Z])

    assert Enum.map(records, & &1.timestamp) ==
             [~U[2026-05-04 10:00:00.000000Z], ~U[2026-05-04 11:00:00.000000Z]]
  end

  test "none without coordinates" do
    record!("historic", ~U[2026-05-04 10:00:00Z])

    assert Weather.historic_records(
             Location.new("Europe/Berlin"),
             ~U[2026-05-04 00:00:00Z],
             ~U[2026-05-05 00:00:00Z]
           ) == []
  end
end
