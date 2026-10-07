defmodule ZiwoasWeb.SolakonLiveConfigTest do
  # The pages with an inverter configured (TestConfigs.file(:inverter): the test
  # config plus monitoring and control). Not async: it swaps the config path,
  # which every process reads; ExUnit runs sync modules after the async ones.
  use ZiwoasWeb.ConnCase

  alias Ziwoas.{Clock, Config, Repo, TestClock}
  alias Ziwoas.Solakon.{Control, Reading}

  @now "2026-10-05T12:00:00+02:00"

  setup do
    previous = Application.fetch_env!(:ziwoas, :config_path)

    Application.put_env(:ziwoas, :config_path, Ziwoas.TestConfigs.file(:inverter))

    TestClock.freeze(@now)

    on_exit(fn ->
      Application.put_env(:ziwoas, :config_path, previous)
      Config.reset()
    end)
  end

  defp page(conn, path), do: conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  defp reading!(seconds_ago) do
    Repo.insert!(%Reading{
      taken_at: @now |> Clock.parse!() |> DateTime.add(-seconds_ago),
      active_power_w: 260.0,
      pv_power_w: 310.0,
      battery_power_w: 50.0,
      battery_soc_pct: 84
    })
  end

  test "the auto-regulation follows an enabled config and the stored state", %{conn: conn} do
    doc = page(conn, "/solakon")
    assert texts(doc, ".stat-value#solakon-control-state") == ["Aktiv"]
    assert texts(doc, "#solakon-control-help") == ["folgt dem gemessenen Verbrauch"]
    assert count(doc, "input#solakon-control-toggle[checked]") == 1
    assert count(doc, "input#solakon-control-toggle[disabled]") == 0

    Repo.insert!(%Control.State{paused: true})
    doc = page(conn, "/solakon")
    assert texts(doc, ".stat-value#solakon-control-state") == ["Pausiert"]
    assert count(doc, "input#solakon-control-toggle[checked]") == 0
  end

  test "a fresh reading shows the battery in the hero and splits the energy flow", %{conn: conn} do
    insert_sample!("fridge", (@now |> Clock.parse!() |> DateTime.to_unix()) - 5, 200.0, 1.0)
    reading!(30)

    doc = page(conn, "/")

    assert count(doc, "#dashboard_hero .col[hidden]") == 0
    assert texts(doc, "#dashboard_hero .display-4") == ["310", "84"]
    assert count(doc, "#dashboard_hero img[alt='Batterie'][src*='solakon_battery_charging']") == 1
    assert texts(doc, "#tile_netbalance_now .stat-value") == ["+60 W"]

    [state] =
      doc
      |> LazyHTML.query("#energy_flow[phx-hook=EnergyFlow]")
      |> LazyHTML.attribute("data-state")

    assert %{"solakon_online" => true, "flows" => %{"solar_to_battery_w" => 50.0}} =
             JSON.decode!(state)
  end

  test "a stale reading leaves the inverter offline", %{conn: conn} do
    reading!(121)

    assert count(page(conn, "/"), "#dashboard_hero .col[hidden]") == 1
  end
end
