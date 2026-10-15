defmodule ZiwoasWeb.DashboardComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Setzkasten.Components.Data
  alias Ziwoas.Energy.{Amount, Balance, LiveState}
  alias Ziwoas.Energy.Flow, as: EnergyFlow
  alias Ziwoas.Energy.Flow.Flows
  alias Ziwoas.Plugs.{Plug, Roster}
  alias ZiwoasWeb.{Components, DashboardComponents}

  defp live(plugs \\ [], flow \\ []) do
    %LiveState{
      plugs: plugs,
      energy_flow:
        struct!(
          %EnergyFlow{
            solakon_online: false,
            home_w: nil,
            solakon_ac_w: nil,
            solar_w: nil,
            battery_soc_pct: nil,
            battery_w: nil,
            battery_state: nil,
            grid_w: nil,
            flows: %Flows{}
          },
          flow
        )
    }
  end

  defp row(id, role, opts \\ []) do
    %LiveState.Row{
      id: id,
      name: Keyword.get(opts, :name, String.capitalize(id)),
      role: role,
      online: Keyword.get(opts, :online, true),
      apower_w: Keyword.get(opts, :apower_w, 0.0),
      last_seen_ts: nil
    }
  end

  defp html(fun, assigns), do: fun |> render_component(assigns) |> LazyHTML.from_fragment()
  defp text(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text() |> squish()

  defp texts(doc, selector),
    do: doc |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  defp attrs(doc, selector, name), do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp squish(text), do: text |> String.split() |> Enum.join(" ")

  describe "hero" do
    defp hero(live),
      do:
        html(&DashboardComponents.hero/1,
          live: live,
          weather_plush: "weather-cloudy-day",
          weather_alt: "bewölkt"
        )

    defp pv(doc), do: text(doc, "#hero_pv > span:first-child")

    test "with a fresh reading the PV half shows solar watts and the battery its SoC" do
      doc =
        hero(
          live([],
            solakon_online: true,
            solar_w: 432.6,
            battery_soc_pct: 57,
            battery_state: :charging
          )
        )

      assert attrs(doc, "#dashboard_hero", "aria-label") == ["Jetzt"]
      assert pv(doc) == "433"
      assert text(doc, "#hero_pv > span:last-child") == "W"
      assert attrs(doc, "img.plush[src*='weather_cloudy_day']", "alt") == ["bewölkt"]
      assert text(doc, "#hero_battery > span:first-child") == "57"
      assert count(doc, "img.plush[alt='Batterie lädt'][src*='solakon_battery_charging']") == 1
    end

    test "solar watts: thousands dot, negative clamped, missing as zero" do
      assert pv(hero(live([], solakon_online: true, solar_w: 1234.6))) == "1.235"
      assert pv(hero(live([], solakon_online: true, solar_w: -3.0))) == "0"
      assert pv(hero(live([], solakon_online: true, solar_w: nil))) == "0"
    end

    test "without the inverter an online producer plug fills in, magnitude only, found by role" do
      doc = hero(live([row("bkw", :producer, apower_w: -300.4)]))
      assert pv(doc) == "300"
      assert count(doc, "#hero_battery") == 0

      plugs = [
        row("fridge", :consumer, apower_w: 111.0),
        row("bkw", :producer, apower_w: 222.0),
        row("washer", :consumer, apower_w: 333.0)
      ]

      assert pv(hero(live(plugs))) == "222"
      assert pv(hero(live([row("bkw", :producer, apower_w: nil)]))) == "0"
    end

    test "with nothing producing online the PV half shows a dash" do
      assert pv(hero(live([row("bkw", :producer, online: false, apower_w: 300.0)]))) == "—"
      assert pv(hero(live([row("fridge", :consumer, apower_w: 50.0)]))) == "—"
    end

    test "an unknown battery state falls back to the normal face and SoC to a dash" do
      doc = hero(live([], solakon_online: true, solar_w: 10.0))

      assert count(doc, "img.plush[alt='Batterie'][src*='solakon_battery_normal']") == 1
      assert text(doc, "#hero_battery > span:first-child") == "—"
    end
  end

  describe "plug bar" do
    defp bar(plugs, rank \\ nil) do
      rank = rank || for(plug <- plugs, plug.role == :consumer, do: plug.id)
      html(&DashboardComponents.plug_bar/1, live: live(plugs), rank: rank)
    end

    defp shares(doc, name),
      do: doc |> LazyHTML.query("#dashboard_plug_shares") |> LazyHTML.attribute(name)

    defp legend(doc), do: texts(doc, "#dashboard_plug_shares li")

    test "one share bar of the consumers' draw, largest first, with each value in its legend" do
      doc = bar([row("fridge", :consumer, apower_w: 80.0), row("tv", :consumer, apower_w: 240.0)])

      assert count(doc, "#dashboard_plug_shares[role=group]") == 1
      assert texts(doc, "#dashboard_plug_shares > div:first-child") == ["Gesamt 320 W"]
      assert shares(doc, "data-plugs") == ["tv fridge"]
      assert legend(doc) == ["Tv 240 W", "Fridge 80 W"]
    end

    test "offline, idle, unmeasured consumers and producers stay out of bar and legend" do
      doc =
        bar([
          row("fridge", :consumer, apower_w: 80.0),
          row("tv", :consumer, online: false, apower_w: 100.0),
          row("lamp", :consumer, apower_w: 0.0),
          row("radio", :consumer, apower_w: nil),
          row("bkw", :producer, name: "Solar", apower_w: -1300.4)
        ])

      assert legend(doc) == ["Fridge 80 W"]
      assert texts(doc, "#dashboard_plug_bar [data-role='producer']") == ["Solar erzeugt 1.300 W"]
      assert legend(bar([row("fridge", :consumer, apower_w: 0.5)])) == ["Fridge 1 W"]
    end

    test "with nothing drawing it says so instead of a bar, without a producer line" do
      doc =
        bar([
          row("fridge", :consumer, online: false, apower_w: 80.0),
          row("bkw", :producer, online: false)
        ])

      assert count(doc, "#dashboard_plug_shares") == 0

      assert texts(doc, "#dashboard_plug_bar [data-role=idle]") == [
               "Gerade zieht keine Steckdose Strom."
             ]

      assert count(doc, "[data-role='producer']") == 0
    end

    test "values are German numbers" do
      doc = bar([row("washer", :consumer, apower_w: 1980.4)])

      assert legend(doc) == ["Washer 1.980 W"]
    end

    test "colours follow the plugs' rank past solar's series" do
      plugs = [
        row("bkw", :producer, apower_w: -300.0),
        row("washer", :consumer, apower_w: 50.0),
        row("fridge", :consumer, apower_w: 300.0)
      ]

      assert shares(bar(plugs), "data-series") == ["3 1"]
      assert shares(bar(plugs, ~w[fridge washer]), "data-series") == ["1 3"]
    end

    test "plugs past the free series are named one by one in grey, all by their draw" do
      plugs =
        for i <- 0..8,
            do: row("p#{i}", :consumer, apower_w: if(i == 8, do: 153.0, else: 10.0 - i))

      doc = bar(plugs)

      assert shares(doc, "data-plugs") == ["p8 p0 p1 p2 p3 p4 p5 p6 p7"]
      assert shares(doc, "data-series") == ["other 1 3 4 5 6 7 8 other"]

      assert legend(doc) ==
               ["P8 153 W", "P0 10 W", "P1 9 W", "P2 8 W", "P3 7 W"] ++
                 ["P4 6 W", "P5 5 W", "P6 4 W", "P7 3 W"]

      assert count(doc, "#dashboard_plug_shares rect.fill-chart-other-fill") == 2
      assert count(doc, "#dashboard_plug_shares li .bg-chart-other-fill") == 2
    end
  end

  describe "tiles" do
    defp tile(assigns), do: html(&Data.stat/1, assigns)

    defp summary(produced_wh, consumed_wh, self_consumed_wh \\ 0.0, savings_eur \\ 0.0) do
      %Balance{
        produced: Amount.wh(produced_wh),
        consumed: Amount.wh(consumed_wh),
        self_consumed: Amount.wh(self_consumed_wh),
        savings_eur: savings_eur,
        date: ~D[2026-10-05]
      }
    end

    defp values(tiles), do: Map.new(tiles, &{&1.id, value(&1)})

    defp value(tile),
      do:
        tile
        |> tile()
        |> LazyHTML.query(".stat-value > span")
        |> Enum.map_join(" ", &LazyHTML.text/1)

    defp descs(tiles), do: Map.new(tiles, &{&1.id, &1[:desc]})

    test "the day's tiles: German kWh, money, the balance as a magnitude and one-decimal shares" do
      values = values(DashboardComponents.summary_tiles(summary(2000.0, 500.0, 375.0, 0.2902)))

      assert values == %{
               "tile_produced" => "2,00 kWh",
               "tile_consumed" => "0,50 kWh",
               "tile_savings" => "0,29 €",
               "tile_net_today" => "1,50 kWh",
               "tile_autarky" => "75,0 %",
               "tile_self_consumption" => "18,8 %"
             }

      assert values(DashboardComponents.summary_tiles(summary(1_234_500.0, 500.0)))[
               "tile_produced"
             ] ==
               "1.234,50 kWh"

      deficit = values(DashboardComponents.summary_tiles(summary(0.0, 500.0, 0.0, nil)))
      assert deficit["tile_net_today"] == "0,50 kWh"
      assert deficit["tile_savings"] == "—", "no price on record: unknown, not free"
      assert deficit["tile_self_consumption"] == "0,0 %"

      assert values(DashboardComponents.summary_tiles(summary(500.0, 500.0)))["tile_net_today"] ==
               "0,00 kWh"
    end

    test "the day's balance names its direction in a word and carries no verdict colour" do
      tile =
        &(DashboardComponents.summary_tiles(&1)
          |> Enum.find(fn t -> t.id == "tile_net_today" end))

      assert tile.(summary(2000.0, 500.0)).desc == "Überschuss"
      assert tile.(summary(500.0, 2000.0)).desc == "Mehrverbrauch"
      assert tile.(summary(500.0, 501.0)).desc == "ausgeglichen"

      for tiles <- [summary(2000.0, 500.0), summary(500.0, 2000.0)],
          tile <- DashboardComponents.summary_tiles(tiles),
          do: refute(Map.has_key?(tile, :tone))
    end

    test "the live tiles: home watts while anything is online, the balance as watts and a word" do
      online = [row("fridge", :consumer)]
      offline = [row("fridge", :consumer, online: false)]
      exporting = DashboardComponents.live_tiles(live(online, home_w: 342.4, grid_w: -120.4))

      assert values(exporting) == %{
               "tile_consumption_now" => "342 W",
               "tile_netbalance_now" => "120 W"
             }

      assert descs(exporting)["tile_netbalance_now"] == "Überschuss"

      importing = DashboardComponents.live_tiles(live(offline, home_w: 342.4, grid_w: 80.0))

      assert values(importing) == %{
               "tile_consumption_now" => "—",
               "tile_netbalance_now" => "80 W"
             }

      assert descs(importing)["tile_netbalance_now"] == "Netzbezug"

      inverter = live(offline, solakon_online: true, home_w: 342.4, grid_w: 0.0)

      assert values(DashboardComponents.live_tiles(inverter)) == %{
               "tile_consumption_now" => "342 W",
               "tile_netbalance_now" => "0 W"
             }

      assert descs(DashboardComponents.live_tiles(inverter))["tile_netbalance_now"] ==
               "ausgeglichen"

      assert values(DashboardComponents.live_tiles(live(online, home_w: nil)))[
               "tile_consumption_now"
             ] == "—"

      assert descs(DashboardComponents.live_tiles(live(online)))["tile_netbalance_now"] == nil
      refute Enum.any?(DashboardComponents.live_tiles(live(online)), &Map.has_key?(&1, :tone))
    end

    test "the consumption names where it comes from right now" do
      from = fn home, solar, battery, grid ->
        [row("fridge", :consumer)]
        |> live(solakon_online: true, flows: Flows.split(home, solar, battery, grid))
        |> DashboardComponents.live_tiles()
        |> descs()
        |> Map.fetch!("tile_consumption_now")
      end

      assert from.(300.0, 0.0, 0.0, 300.0) == "aus dem Netz"
      assert from.(300.0, 400.0, 0.0, -100.0) == "aus PV"
      assert from.(300.0, 0.0, -300.0, 0.0) == "aus der Batterie"
      assert from.(300.0, 200.0, 0.0, 100.0) == "aus PV und Netz"
      assert from.(300.0, 200.0, -50.0, 50.0) == "aus PV, Batterie und Netz"
      assert from.(0.0, 0.0, 0.0, 0.0) == nil

      assert DashboardComponents.live_tiles(live([row("fridge", :consumer)]))
             |> hd()
             |> Map.get(:desc) == nil
    end

    test "summary and live tiles enumerate every broadcast target once" do
      ids =
        Enum.map(
          DashboardComponents.summary_tiles(summary(0.0, 0.0)) ++
            DashboardComponents.live_tiles(live()),
          & &1.id
        )

      assert ids ==
               ~w[tile_produced tile_consumed tile_savings tile_net_today tile_autarky tile_self_consumption tile_consumption_now tile_netbalance_now]
    end
  end

  describe "today's charts" do
    defp today_charts(chart, consumers \\ [{"fridge", "Kühlschrank"}]),
      do:
        html(&DashboardComponents.today_charts/1,
          chart: chart,
          producers: ["Balkonkraftwerk"],
          consumers: consumers,
          rank: Enum.map(consumers, &elem(&1, 0)),
          roster: Roster.new([%Plug{id: "bkw", name: "Balkonkraftwerk", role: :producer}]),
          zone: "Europe/Berlin"
        )

    @chart %{
      energy: %{
        hours: [1_780_308_000_000, 1_780_311_600_000],
        produced_kwh: [0.5, 0.25],
        consumers: [%{plug_id: "fridge", name: "Kühlschrank", kwh: [0.1, 0.0]}]
      },
      power: %{
        series: [
          %{plug_id: "bkw", name: "Balkonkraftwerk", role: :producer, points: [[1, 420.0]]},
          %{plug_id: "fridge", name: "Kühlschrank", role: :consumer, points: [[1, 80.0]]}
        ]
      }
    }

    test "until connected each card shows its skeleton, no hook" do
      doc = today_charts(nil)

      assert attrs(doc, "section.card[aria-busy=true]", "id") == ~w[today_energy today_power]
      assert count(doc, "[phx-hook]") == 0
    end

    test "each chart is a TodayChart hook with its payload and a summary of its values" do
      doc = today_charts(@chart)

      assert attrs(doc, "[phx-hook=TodayChart]", "data-chart") == ~w[energy power]
      [energy] = attrs(doc, "#today_energy-chart", "data-payload")
      assert JSON.decode!(energy)["produced_kwh"] == [0.5, 0.25]

      assert attrs(doc, "#today_energy [role=img]", "aria-label") == [
               "Energie der letzten 24 Stunden: 0,75 kWh erzeugt, 0,10 kWh an den Steckdosen verbraucht."
             ]

      assert attrs(doc, "#today_power [role=img]", "aria-label") == [
               "Leistung der letzten 24 Stunden: höchstens 420 W erzeugt, höchstens 80 W verbraucht."
             ]

      assert texts(doc, "tbody#today_energy_data tr") == [
               "12:00 0,50 kWh 0,10 kWh",
               "13:00 0,25 kWh 0,00 kWh"
             ]
    end

    test "without a reading in the window an empty state takes both charts' place" do
      quiet = put_in(@chart, [:power, :series], [%{role: :producer, points: []}])
      doc = today_charts(quiet)

      assert texts(doc, "#today_empty p.font-semibold") == [
               "Keine Messwerte der letzten 24 Stunden"
             ]

      assert count(doc, "#today_energy, #today_power") == 0
    end

    test "the legends name the series; consumers past the free series share Weitere" do
      assert texts(today_charts(@chart), "#today_energy ul li") == ["Erzeugt", "Kühlschrank"]

      assert texts(today_charts(@chart), "#today_power ul li") == [
               "Balkonkraftwerk",
               "Gesamtverbrauch"
             ]

      many = today_charts(@chart, for(i <- 1..9, do: {"d#{i}", "Dose #{i}"}))
      items = texts(many, "#today_energy ul li")

      assert length(items) == 9
      assert List.last(items) == "Weitere"
      refute "Dose 8" in items
    end
  end

  describe "history chart" do
    test "a HistoryChart hook with the days as payload, a summary and a table" do
      points = [
        %{date: "2026-10-03", energy_wh: 2100.0},
        %{date: "2026-10-04", energy_wh: 900.0}
      ]

      doc = html(&DashboardComponents.history_chart/1, points: points)

      assert attrs(doc, "#history-chart[phx-hook=HistoryChart]", "data-payload") == [
               JSON.encode!(points)
             ]

      assert attrs(doc, "#history [role=img]", "aria-label") == [
               "Ertrag der letzten 14 Tage: 3,00 kWh, am meisten am 03.10. mit 2,10 kWh."
             ]

      assert texts(doc, "tbody#history_data tr") == ["03.10. 2,10 kWh", "04.10. 0,90 kWh"]
    end

    test "without a day yet an empty state takes the chart's place" do
      doc = html(&DashboardComponents.history_chart/1, points: [])

      assert texts(doc, "#history_empty p.font-semibold") == ["Noch kein Ertrag aufgezeichnet"]
      assert count(doc, "#history") == 0
    end
  end

  describe "energy flow" do
    defp energy_flow(live),
      do: html(&Components.EnergyFlow.energy_flow/1, live: live)

    defp ring_value(doc, ring), do: text(doc, ".ef-ring[data-ring=#{ring}] .ef-value")
    defp ring_name(doc, ring), do: text(doc, ".ef-name[data-name=#{ring}]")

    test "the card is the EnergyFlow hook with the flow as JSON in data-state" do
      flows = Flows.split(130.0, 420.0, 0.0, -290.0)

      doc =
        energy_flow(live([], solakon_online: true, solar_w: 420.0, home_w: 130.0, flows: flows))

      assert count(doc, "section.card#energy_flow[phx-hook=EnergyFlow]") == 1
      assert texts(doc, "#energy_flow h2.card-title") == ["Energiefluss"]
      state = doc |> attrs("#energy_flow", "data-state") |> hd() |> JSON.decode!()

      assert {state["solakon_online"], state["solar_w"], state["flows"]["solar_to_home_w"]} ==
               {true, 420.0, 130.0}

      stale = live() |> energy_flow() |> attrs("#energy_flow", "data-state") |> hd()
      assert %{"solakon_online" => false, "solar_w" => nil} = JSON.decode!(stale)
    end

    test "four rings with a box each, placed over the ring, six channels with their dots" do
      doc = energy_flow(live())

      assert attrs(doc, ".energy-flow svg circle[data-ring]", "data-ring") ==
               ~w[pv grid consumer battery]

      assert attrs(doc, ".energy-flow > .ef-ring", "style") == [
               "left: 50%; top: 25%; width: 20%; height: 25%",
               "left: 14.5%; top: 53.125%; width: 20%; height: 25%",
               "left: 85.5%; top: 53.125%; width: 20%; height: 25%",
               "left: 50%; top: 81.25%; width: 20%; height: 25%"
             ]

      assert count(doc, ".energy-flow svg g[clip-path='url(#ef-clip)'] > path[data-ef^=efLine]") ==
               6

      assert count(doc, ".energy-flow svg g[data-ef^='efDots']") == 6

      assert count(doc, ".ef-ring[data-ring='pv'] > img.plush[src*='sonne']") == 1
      assert count(doc, ".ef-ring[data-ring='consumer'] > img.plush[src*='icon_haus']") == 1
    end

    test "the rings' values and names: magnitudes in watts, directions in words" do
      online =
        live([],
          solakon_online: true,
          solar_w: 1420.4,
          home_w: 342.4,
          grid_w: -120.0,
          battery_w: 80.0,
          battery_soc_pct: 57,
          battery_state: :charging
        )

      doc = energy_flow(online)

      assert {ring_value(doc, :pv), ring_value(doc, :consumer)} == {"1.420 W", "342 W"}
      assert {ring_value(doc, :grid), ring_name(doc, :grid)} == {"120 W", "Überschuss"}

      assert {ring_value(doc, :battery), ring_name(doc, :battery)} ==
               {"80 W", "Batterie lädt\u2060\u00A0· 57 %"}

      assert count(doc, ".ef-ring[data-ring=battery] img[src*='solakon_battery_charging']") == 1

      importing = energy_flow(live([], grid_w: 300.0, battery_w: -0.4))
      assert ring_name(importing, :grid) == "Netzbezug"
      assert ring_name(importing, :battery) == "Batterie"
      assert ring_value(importing, :pv) == "— W"
      assert ring_name(energy_flow(live([], battery_w: -50.0)), :battery) == "Batterie entlädt"
    end

    test "the battery picture and its words follow the state, the normal ones when unknown" do
      assert Components.EnergyFlow.battery_plush(:charging) == "battery-charging"
      assert Components.EnergyFlow.battery_plush(nil) == "battery"
      assert Components.EnergyFlow.battery_alt(:fault) == "Batteriefehler"
      assert Components.EnergyFlow.battery_alt(:unknown) == "Batterie"
    end
  end
end
