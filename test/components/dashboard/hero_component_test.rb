require "test_helper"
require_relative "live_test_support"

class Dashboard::HeroComponentTest < ViewComponent::TestCase
  include Dashboard::LiveTestSupport

  cover "Dashboard::HeroComponent*"

  def render_hero(l)
    render_inline(Dashboard::HeroComponent.new(live: l, weather_asset: "icon_sonne.webp", weather_alt: "Sonne"))
  end

  test "with a fresh reading the PV half shows solar watts and the battery its SoC" do
    rendered = render_hero(live(flow: { solakon_online: true, solar_w: 432.6,
                                        battery_soc_pct: 57, battery_state: "charging" }))

    assert rendered.css("#dashboard_hero").any?
    assert_equal "433", rendered.css(".hero-half:first-child .hero-number").text
    assert_equal "Sonne", rendered.css(".hero-half:first-child img.hero-icon").attr("alt").value
    assert rendered.css(".hero-half:last-child[hidden]").none?
    assert_equal "57", rendered.css(".hero-half:last-child .hero-number").text
    assert rendered.css("img.hero-icon-battery[src*='solakon_battery_charging']").any?
  end

  test "negative solar watts clamp to zero" do
    rendered = render_hero(live(flow: { solakon_online: true, solar_w: -3.0 }))

    assert_equal "0", rendered.css(".hero-half:first-child .hero-number").text
  end

  test "without the inverter an online producer plug fills in, magnitude only" do
    rendered = render_hero(live(plugs: [ row(id: "bkw", role: :producer, apower_w: -300.4) ]))

    assert_equal "300", rendered.css(".hero-half:first-child .hero-number").text
    assert rendered.css(".hero-half:last-child[hidden]").any?
  end

  test "with nothing online the PV half shows a dash and the battery stays hidden" do
    rendered = render_hero(live(plugs: [ row(id: "bkw", role: :producer, online: false, apower_w: 300.0) ]))

    assert_equal "—", rendered.css(".hero-half:first-child .hero-number").text
    assert rendered.css(".hero-half:last-child[hidden]").any?
  end

  test "an unknown battery state falls back to the normal face and SoC to a dash" do
    rendered = render_hero(live(flow: { solakon_online: true, solar_w: 10.0,
                                        battery_soc_pct: nil, battery_state: nil }))

    assert rendered.css("img.hero-icon-battery[src*='solakon_battery_normal']").any?
    assert_equal "—", rendered.css(".hero-half:last-child .hero-number").text
  end

  test "a missing solar reading while the inverter is online falls back to zero" do
    rendered = render_hero(live(flow: { solakon_online: true, solar_w: nil }))

    assert_equal "0", rendered.css(".hero-half:first-child .hero-number").text
  end

  test "the producer plug is found by role, not by position" do
    plugs = [
      row(id: "fridge", role: :consumer, online: true, apower_w: 111.0),
      row(id: "bkw", role: :producer, online: true, apower_w: 222.0),
      row(id: "washer", role: :consumer, online: true, apower_w: 333.0)
    ]

    rendered = render_hero(live(plugs: plugs))

    assert_equal "222", rendered.css(".hero-half:first-child .hero-number").text
  end

  test "with no producer plug at all and no inverter the PV half shows a dash" do
    rendered = render_hero(live(plugs: [ row(id: "fridge", role: :consumer, online: true, apower_w: 50.0) ]))

    assert_equal "—", rendered.css(".hero-half:first-child .hero-number").text
  end

  test "a missing apower reading on an online producer plug falls back to zero" do
    rendered = render_hero(live(plugs: [ row(id: "bkw", role: :producer, online: true, apower_w: nil) ]))

    assert_equal "0", rendered.css(".hero-half:first-child .hero-number").text
  end
end
