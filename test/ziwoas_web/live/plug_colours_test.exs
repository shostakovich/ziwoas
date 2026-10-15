defmodule ZiwoasWeb.PlugColoursTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Clock, Repo, TestClock, TestConfigs}
  alias Ziwoas.Plugs.DailyTotal

  @now "2026-10-05T12:00:00+02:00"
  @today ~D[2026-10-05]
  @plugs """
    - id: tv
      name: TV
      role: consumer
    - id: washer
      name: Washer
      role: consumer
  """

  setup do
    TestClock.freeze(@now)
    TestConfigs.put(TestConfigs.located(@plugs))

    for {plug_id, days_ago, wh} <- [{"washer", 3, 900.0}, {"tv", 2, 500.0}, {"fridge", 1, 100.0}] do
      Repo.insert!(%DailyTotal{
        plug_id: plug_id,
        date: Date.add(@today, -days_ago),
        energy_wh: wh
      })
    end

    now_ts = DateTime.to_unix(Clock.now())
    for plug_id <- ~w[fridge tv washer], do: insert_sample!(plug_id, now_ts - 5, 50.0, 10.0)
    :ok
  end

  defp attrs(html, selector, name),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp payload(html, selector),
    do: html |> attrs(selector, "data-payload") |> hd() |> JSON.decode!()

  test "a plug keeps its colour by its 30-day consumption on Home and in the reports", %{
    conn: conn
  } do
    {:ok, home, _html} = live(conn, ~p"/")
    home = render(home)

    {:ok, reports, _html} = live(conn, ~p"/reports?preset=last_7")
    reports = render(reports)

    assert attrs(home, "#dashboard_plug_shares", "data-plugs") == ["fridge tv washer"]
    assert attrs(home, "#dashboard_plug_shares", "data-series") == ["4 3 1"]

    assert payload(home, "#today_energy-chart")["consumer_order"] == ~w[washer tv fridge]
    assert payload(reports, "#report_daily-chart")["consumer_order"] == ~w[washer tv fridge]
    assert payload(reports, "#report_detail-chart")["consumer_order"] == ~w[washer tv fridge]
  end

  test "the plugs past the colours reach the charts by name and value, for Weitere's tooltip", %{
    conn: conn
  } do
    extra = for i <- 1..6, do: "  - id: d#{i}\n    name: Dose #{i}\n    role: consumer\n"
    TestConfigs.put(TestConfigs.located(Enum.join([@plugs | extra])))

    now_ts = DateTime.to_unix(Clock.now())
    for i <- 1..6, do: insert_sample!("d#{i}", now_ts - 5, 60.0, 10.0)

    {:ok, home, _html} = live(conn, ~p"/")
    energy = payload(render(home), "#today_energy-chart")

    assert Enum.drop(energy["consumer_order"], 7) == ~w[d5 d6]

    assert for(
             consumer <- energy["consumers"],
             consumer["plug_id"] in ~w[d5 d6],
             do: {consumer["name"], Enum.sum(consumer["kwh"])}
           ) == [{"Dose 5", 0.001}, {"Dose 6", 0.001}]
  end

  test "a custom report range keeps the 30-day colours", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports?start_date=2026-10-04&end_date=2026-10-04")

    assert payload(render(view), "#report_daily-chart")["consumer_order"] == ~w[washer tv fridge]
  end
end
