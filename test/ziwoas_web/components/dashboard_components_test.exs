defmodule ZiwoasWeb.DashboardComponentsTest do
  # In-memory live states, no database.
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Ziwoas.Energy.{Amount, Balance, LiveState}
  alias Ziwoas.Energy.Flow, as: EnergyFlow
  alias Ziwoas.Energy.Flow.Flows
  alias ZiwoasWeb.{Components, CoreComponents, DashboardComponents}

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
          weather_asset: "icon_sonne.webp",
          weather_alt: "Sonne"
        )

    defp pv(doc), do: text(doc, "#dashboard_hero .col:first-child .display-4")

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

      assert pv(doc) == "433"
      assert attrs(doc, "#dashboard_hero .col:first-child img.hero-icon", "alt") == ["Sonne"]
      assert count(doc, "#dashboard_hero .col:last-child[hidden]") == 0
      assert text(doc, "#dashboard_hero .col:last-child .display-4") == "57"
      assert count(doc, "img.hero-icon[alt='Batterie'][src*='solakon_battery_charging']") == 1
    end

    test "solar watts: thousands dot, negative clamped, missing as zero" do
      assert pv(hero(live([], solakon_online: true, solar_w: 1234.6))) == "1.235"
      assert pv(hero(live([], solakon_online: true, solar_w: -3.0))) == "0"
      assert pv(hero(live([], solakon_online: true, solar_w: nil))) == "0"
    end

    test "without the inverter an online producer plug fills in, magnitude only, found by role" do
      doc = hero(live([row("bkw", :producer, apower_w: -300.4)]))
      assert pv(doc) == "300"
      assert count(doc, "#dashboard_hero .col:last-child[hidden]") == 1

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

      assert count(doc, "img.hero-icon[alt='Batterie'][src*='solakon_battery_normal']") == 1
      assert text(doc, "#dashboard_hero .col:last-child .display-4") == "—"
    end
  end

  describe "plug bar" do
    defp bar(plugs), do: html(&DashboardComponents.plug_bar/1, live: live(plugs))

    defp segments(doc),
      do:
        doc
        |> LazyHTML.query("#dashboard_plug_bar .progress-stacked > .progress")
        |> Enum.to_list()

    defp attr(node, name), do: node |> LazyHTML.attribute(name) |> hd()

    defp color(node, selector),
      do:
        Regex.run(
          ~r/background-color: (var\(--[\w-]+\))/,
          node |> LazyHTML.query(selector) |> attr("style")
        )
        |> List.last()

    defp legend(doc),
      do: texts(doc, "#dashboard_plug_bar ul[aria-label='Legende'] > li .plug-bar-name")

    test "consumers stack by falling wattage with widths summing to 100 percent" do
      doc = bar([row("fridge", :consumer, apower_w: 80.0), row("tv", :consumer, apower_w: 240.0)])
      [tv, fridge] = segments(doc)

      assert attr(tv, "style") == "width: 75%"
      assert attr(tv, "title") == "Tv · 240 W"
      assert attr(tv, "aria-label") == "Tv"
      assert attr(tv, "aria-valuenow") == "75"
      assert attr(fridge, "style") == "width: 25%"
      assert text(doc, "#dashboard_plug_bar strong") == "320 W"
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

      assert length(segments(doc)) == 1
      assert legend(doc) == ["Fridge"]
      assert texts(doc, "#dashboard_plug_bar [data-role='producer']") == ["Solar erzeugt 1.300 W"]
      assert length(segments(bar([row("fridge", :consumer, apower_w: 0.5)]))) == 1
    end

    test "with nothing online the bar renders empty at 0 W, without a producer line" do
      doc =
        bar([
          row("fridge", :consumer, online: false, apower_w: 80.0),
          row("bkw", :producer, online: false)
        ])

      assert segments(doc) == []
      assert text(doc, "#dashboard_plug_bar strong") == "0 W"
      assert count(doc, "[data-role='producer']") == 0
    end

    test "legend values and segment titles are German numbers" do
      doc = bar([row("washer", :consumer, apower_w: 1980.4)])

      assert texts(doc, "ul[aria-label='Legende'] > li .text-nowrap") == ["1.980 W"]
      assert attr(hd(segments(doc)), "title") == "Washer · 1.980 W"
    end

    test "color follows the consumer's roster position and wraps after ten" do
      doc =
        bar([
          row("bkw", :producer, apower_w: -300.0),
          row("washer", :consumer, apower_w: 50.0),
          row("fridge", :consumer, apower_w: 300.0)
        ])

      [fridge, _washer] = segments(doc)
      assert color(fridge, ".progress-bar") == "var(--viz-2)"
      assert doc |> LazyHTML.query("ul li") |> Enum.at(1) |> color(".badge") == "var(--viz-1)"

      many = bar(for i <- 0..10, do: row("p#{i}", :consumer, apower_w: 100.0 - i))
      colors = Enum.map(segments(many), &color(&1, ".progress-bar"))
      assert Enum.at(colors, 9) == "var(--viz-10)"
      assert Enum.at(colors, 10) == hd(colors)
    end
  end

  describe "tiles" do
    defp tile(assigns), do: html(&CoreComponents.tile/1, assigns)

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
    defp value(tile), do: tile |> tile() |> text(".stat-value")

    test "a tile carries its id, label and value, the unit set smaller, a caption under it" do
      doc = tile(id: "tile_x", label: "Label", number: "1", unit: "W")
      assert text(doc, "div.col#tile_x .card .stat .stat-label") == "Label"

      assert text(
               doc,
               ".card.h-100 > .card-body.h-100.d-flex.flex-column > .stat.flex-grow-1 > .stat-value.mt-auto"
             ) == "1 W"

      assert text(doc, ".stat-value span.fs-5") == "W"

      assert count(tile(label: "Bilanz", number: "—"), ".stat-value span") == 0
      assert count(tile(label: "Bilanz", number: "—"), "div.col[id]") == 0

      captioned = tile(label: "Panel 1", number: "211 W", caption: "41,0 V · 5,12 A")
      assert text(captioned, ".stat-value + span.small.text-body-secondary") == "41,0 V · 5,12 A"
      assert count(tile(label: "Panel 1", number: "211 W"), ".stat-value + span") == 0
    end

    test "the day's tiles: German kWh, money, a signed balance and one-decimal shares" do
      values = values(DashboardComponents.summary_tiles(summary(2000.0, 500.0, 375.0, 0.2902)))

      assert values == %{
               "tile_produced" => "2,00 kWh",
               "tile_consumed" => "0,50 kWh",
               "tile_savings" => "0,29 €",
               "tile_net_today" => "+1,50 kWh",
               "tile_autarky" => "75,0 %",
               "tile_self_consumption" => "18,8 %"
             }

      assert values(DashboardComponents.summary_tiles(summary(1_234_500.0, 500.0)))[
               "tile_produced"
             ] ==
               "1.234,50 kWh"

      deficit = values(DashboardComponents.summary_tiles(summary(0.0, 500.0, 0.0, nil)))
      assert deficit["tile_net_today"] == "−0,50 kWh"
      assert deficit["tile_savings"] == "—", "no price on record: unknown, not free"
      assert deficit["tile_self_consumption"] == "0,0 %"

      assert values(DashboardComponents.summary_tiles(summary(500.0, 500.0)))["tile_net_today"] ==
               "+0,00 kWh"
    end

    test "the live tiles: home watts while anything is online, export as plus" do
      online = [row("fridge", :consumer)]
      offline = [row("fridge", :consumer, online: false)]

      assert values(DashboardComponents.live_tiles(live(online, home_w: 342.4, grid_w: -120.4))) ==
               %{
                 "tile_consumption_now" => "342 W",
                 "tile_netbalance_now" => "+120 W"
               }

      assert values(DashboardComponents.live_tiles(live(offline, home_w: 342.4, grid_w: 80.0))) ==
               %{
                 "tile_consumption_now" => "—",
                 "tile_netbalance_now" => "−80 W"
               }

      inverter = live(offline, solakon_online: true, home_w: 342.4, grid_w: 0.0)

      assert values(DashboardComponents.live_tiles(inverter)) == %{
               "tile_consumption_now" => "342 W",
               "tile_netbalance_now" => "+0 W"
             }

      assert values(DashboardComponents.live_tiles(live(online, home_w: nil)))[
               "tile_consumption_now"
             ] == "—"
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

  describe "energy flow" do
    defp energy_flow(live),
      do:
        html(&Components.EnergyFlow.energy_flow/1,
          live: live,
          pv_asset: "icon_sonne.webp",
          pv_alt: "PV"
        )

    test "the card is the EnergyFlow hook with the flow as JSON in data-state" do
      flows = Flows.split(130.0, 420.0, 0.0, -290.0)

      doc =
        energy_flow(live([], solakon_online: true, solar_w: 420.0, home_w: 130.0, flows: flows))

      assert count(doc, "section.card.energy-flow-card#energy_flow[phx-hook=EnergyFlow]") == 1
      assert texts(doc, "#energy_flow h2.card-title") == ["Energiefluss"]
      state = doc |> attrs("#energy_flow", "data-state") |> hd() |> JSON.decode!()

      assert {state["solakon_online"], state["solar_w"], state["flows"]["solar_to_home_w"]} ==
               {true, 420.0, 130.0}

      stale = live() |> energy_flow() |> attrs("#energy_flow", "data-state") |> hd()
      assert %{"solakon_online" => false, "solar_w" => nil} = JSON.decode!(stale)
    end

    test "four rings with a box each, placed over the ring, six channels in theme tokens" do
      doc = energy_flow(live())

      assert attrs(doc, ".energy-flow svg circle[data-ring]", "data-ring") ==
               ~w[pv grid consumer battery]

      assert attrs(doc, ".energy-flow > .ef-ring", "style") == [
               "left: 50%; top: 25%; width: 20%; height: 25%",
               "left: 14.5%; top: 53.125%; width: 20%; height: 25%",
               "left: 85.5%; top: 53.125%; width: 20%; height: 25%",
               "left: 50%; top: 81.25%; width: 20%; height: 25%"
             ]

      assert count(doc, ".energy-flow svg g[clip-path='url(#ef-clip)'] > path.ef-link") == 6

      assert count(doc, ".energy-flow svg g[clip-path='url(#ef-clip)'] > g[data-ef^='efDots']") ==
               6

      assert count(doc, "span.ef-value.tabular-nums.fw-semibold") == 4

      assert count(doc, ".ef-ring[data-ring='pv'] > img.ef-icon[src*='icon_sonne'][alt='PV']") ==
               1

      battery = "img.ef-icon[data-ef='efBatteryImage'][src*='solakon_battery_normal']"

      assert attrs(doc, battery, "data-battery-state-charging") == [
               "/images/solakon_battery_charging.webp"
             ]

      assert attrs(doc, battery, "data-battery-state-fault") == [
               "/images/solakon_battery_fault.webp"
             ]
    end

    test "the battery picture follows the state, the normal one when unknown" do
      assert Components.EnergyFlow.battery_asset(:charging) == "solakon_battery_charging.webp"
      assert Components.EnergyFlow.battery_asset(nil) == "solakon_battery_normal.webp"
    end
  end
end
