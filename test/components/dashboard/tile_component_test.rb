require "test_helper"
require_relative "live_test_support"

class Dashboard::TileComponentTest < ViewComponent::TestCase
  include Dashboard::LiveTestSupport

  cover "Dashboard::TileComponent*"

  FakeSummary = Struct.new(:produced, :consumed, :savings_eur,
                           :autarky_ratio, :self_consumption_ratio, keyword_init: true)

  def summary(produced_wh: 0.0, consumed_wh: 0.0, savings_eur: 0.0,
              autarky_ratio: 0.0, self_consumption_ratio: 0.0)
    FakeSummary.new(produced: Energy.wh(produced_wh), consumed: Energy.wh(consumed_wh),
                    savings_eur: savings_eur, autarky_ratio: autarky_ratio,
                    self_consumption_ratio: self_consumption_ratio)
  end

  test "a tile carries its id, label and value" do
    rendered = render_inline(Dashboard::TileComponent.new(id: "tile_x", label: "Label", value: "1 W"))

    assert rendered.css("div.tile#tile_x").any?
    assert_equal "Label", rendered.css(".tile-label").text
    assert_equal "1 W", rendered.css(".tile-value").text
  end

  test "produced formats Wh as German kWh with thousands separator" do
    rendered = render_inline(Dashboard::TileComponent.produced(summary(produced_wh: 1_234_500.0)))

    assert rendered.css("#tile_produced").any?
    assert_equal "Erzeugt heute", rendered.css(".tile-label").text
    assert_equal "1.234,50 kWh", rendered.css(".tile-value").text
  end

  test "consumed and savings round to two decimals" do
    consumed = render_inline(Dashboard::TileComponent.consumed(summary(consumed_wh: 1234.5)))
    assert_equal "Verbraucht heute", consumed.css(".tile-label").text
    assert_equal "1,23 kWh", consumed.css(".tile-value").text

    savings = render_inline(Dashboard::TileComponent.savings(summary(savings_eur: 0.2902)))
    assert_equal "Gespart heute", savings.css(".tile-label").text
    assert_equal "0,29 €", savings.css(".tile-value").text
  end

  test "net_today carries a plus for a surplus and a minus for a deficit" do
    surplus = summary(produced_wh: 2000.0, consumed_wh: 500.0)
    deficit = summary(produced_wh: 0.0, consumed_wh: 500.0)

    rendered = render_inline(Dashboard::TileComponent.net_today(surplus))
    assert_equal "Bilanz heute", rendered.css(".tile-label").text
    assert_equal "+1,50 kWh", rendered.css(".tile-value").text
    assert_equal "-0,50 kWh", render_inline(Dashboard::TileComponent.net_today(deficit)).css(".tile-value").text
  end

  test "net_today carries a plus even for an exact balance" do
    balanced = summary(produced_wh: 500.0, consumed_wh: 500.0)

    assert_equal "+0,00 kWh", render_inline(Dashboard::TileComponent.net_today(balanced)).css(".tile-value").text
  end

  test "ratios render as one-decimal percent" do
    s = summary(autarky_ratio: 0.375, self_consumption_ratio: 0.5)

    autarky = render_inline(Dashboard::TileComponent.autarky(s))
    assert_equal "Autarkie heute", autarky.css(".tile-label").text
    assert_equal "37,5 %", autarky.css(".tile-value").text

    self_consumption = render_inline(Dashboard::TileComponent.self_consumption(s))
    assert_equal "Eigenverbrauch", self_consumption.css(".tile-label").text
    assert_equal "50,0 %", self_consumption.css(".tile-value").text
  end

  test "a ratio with more than one decimal digit rounds to one" do
    s = summary(autarky_ratio: 1 / 3.0)

    assert_equal "33,3 %", render_inline(Dashboard::TileComponent.autarky(s)).css(".tile-value").text
  end

  test "a missing ratio falls back to zero percent" do
    s = summary(autarky_ratio: nil)

    assert_equal "0,0 %", render_inline(Dashboard::TileComponent.autarky(s)).css(".tile-value").text
  end

  test "consumption_now shows the flow's home watts while anything is online" do
    l = live(plugs: [ row(id: "fridge", role: :consumer, online: true) ],
             flow: { home_w: 342.4 })

    rendered = render_inline(Dashboard::TileComponent.consumption_now(l))
    assert rendered.css("#tile_consumption_now").any?
    assert_equal "Verbrauch jetzt", rendered.css(".tile-label").text
    assert_equal "342 W", rendered.css(".tile-value").text
  end

  test "consumption_now falls to a dash when everything is offline" do
    l = live(plugs: [ row(id: "fridge", role: :consumer, online: false) ],
             flow: { home_w: 342.4 })

    assert_equal "—", render_inline(Dashboard::TileComponent.consumption_now(l)).css(".tile-value").text
  end

  test "consumption_now counts the inverter itself as online even with no online plug" do
    l = live(plugs: [ row(id: "fridge", role: :consumer, online: false) ],
             flow: { solakon_online: true, home_w: 342.4 })

    assert_equal "342 W", render_inline(Dashboard::TileComponent.consumption_now(l)).css(".tile-value").text
  end

  test "consumption_now counts as online when only one of several plugs is online" do
    l = live(plugs: [ row(id: "fridge", role: :consumer, online: true),
                      row(id: "washer", role: :consumer, online: false) ],
             flow: { home_w: 342.4 })

    assert_equal "342 W", render_inline(Dashboard::TileComponent.consumption_now(l)).css(".tile-value").text
  end

  test "consumption_now falls to a dash when online but the flow has no home watts" do
    l = live(plugs: [ row(id: "fridge", role: :consumer, online: true) ], flow: { home_w: nil })

    assert_equal "—", render_inline(Dashboard::TileComponent.consumption_now(l)).css(".tile-value").text
  end

  test "netbalance_now reads export as plus and import as minus" do
    export = live(flow: { grid_w: -120.4 })
    import = live(flow: { grid_w: 80.0 })
    unknown = live(flow: { grid_w: nil })

    rendered = render_inline(Dashboard::TileComponent.netbalance_now(export))
    assert_equal "Bilanz jetzt", rendered.css(".tile-label").text
    assert_equal "+120 W", rendered.css(".tile-value").text
    assert_equal "−80 W", render_inline(Dashboard::TileComponent.netbalance_now(import)).css(".tile-value").text
    assert_equal "—", render_inline(Dashboard::TileComponent.netbalance_now(unknown)).css(".tile-value").text
  end

  test "netbalance_now treats exactly zero as export and a small import as import" do
    zero = live(flow: { grid_w: 0.0 })
    one = live(flow: { grid_w: 1.0 })

    assert_equal "+0 W", render_inline(Dashboard::TileComponent.netbalance_now(zero)).css(".tile-value").text
    assert_equal "−1 W", render_inline(Dashboard::TileComponent.netbalance_now(one)).css(".tile-value").text
  end

  test "summary_tiles and live_tiles enumerate every broadcast target once" do
    ids = (Dashboard::TileComponent.summary_tiles(summary) +
           Dashboard::TileComponent.live_tiles(live)).map(&:id)

    assert_equal %w[tile_produced tile_consumed tile_savings tile_net_today
                    tile_autarky tile_self_consumption
                    tile_consumption_now tile_netbalance_now], ids
  end
end
