require_relative "application_system_test_case"

class DashboardRefreshTest < ApplicationSystemTestCase
  setup do
    Plugs::Sample.delete_all
    SolakonReading.delete_all
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 2, apower_w: -420.0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: now - 2, apower_w: 80.0, aenergy_wh: 500.0)
  end

  test "the dashboard arrives fully rendered from the server" do
    visit root_path

    assert_selector "#tile_consumption_now .tile-value", text: "80 W"
    assert_selector "#dashboard_plug_bar .plug-bar-meta b", text: "80 W"
    assert_selector "#dashboard_hero .hero-number", text: "420"
  end

  test "a Live-Bild that is no longer kept current is dimmed, not emptied" do
    visit root_path
    assert_selector "#tile_consumption_now .tile-value", text: /\d+ W/
    consumption = find("#tile_consumption_now .tile-value").text

    skip_ahead_ten_minutes

    assert_selector "[data-controller~='live-freshness'].live-stale"
    assert_equal consumption, find("#tile_consumption_now .tile-value").text
  end

  test "a beat after a gap ends the dimming and asks the charts for a fresh Bild" do
    visit root_path
    assert_selector "#tile_consumption_now .tile-value", text: /\d+ W/

    skip_ahead_ten_minutes
    assert_selector "[data-controller~='live-freshness'].live-stale"

    page.execute_script(<<~JS)
      window.__resynced = false
      document.addEventListener("live-freshness:resync", () => { window.__resynced = true })
    JS
    inject_stream(beat_stream(flow_state(solar_to_home_w: 0)))

    assert_no_selector "[data-controller~='live-freshness'].live-stale"
    assert_equal true, wait_for { page.evaluate_script("window.__resynced") }
  end

  test "a changed pace speeds the dots up in place instead of restarting them" do
    visit root_path

    inject_stream(beat_stream(flow_state(solar_to_home_w: 100)))
    assert_selector "[data-ef='efDotsSolarHome'] circle", visible: :all, count: 3
    mark_dots
    rate_before = dot_playback_rate

    # Well beyond the 5% guard: the old code tore the dots down here.
    inject_stream(beat_stream(flow_state(solar_to_home_w: 400)))
    assert_selector "#energy_flow_state[data-state*='400']", visible: :all

    assert_equal true, wait_for { dot_playback_rate != rate_before }
    assert_equal true, dots_survived?, "the dots must keep their identity across a pace change"
    assert_operator dot_playback_rate, :>, rate_before, "more watts must mean a faster lap"
  end

  test "a channel that falls silent loses its dots" do
    visit root_path

    inject_stream(beat_stream(flow_state(solar_to_home_w: 100)))
    assert_selector "[data-ef='efDotsSolarHome'] circle", visible: :all, count: 3

    inject_stream(beat_stream(flow_state(solar_to_home_w: 0)))
    assert_no_selector "[data-ef='efDotsSolarHome'] circle", visible: :all
  end

  private

  def flow_state(solar_to_home_w:)
    {
      solakon_online: true, home_w: solar_to_home_w,
      solakon_ac_w: solar_to_home_w, solar_w: solar_to_home_w,
      battery_soc_pct: 50, battery_w: 0, battery_state: "normal", grid_w: 0,
      flows: { solar_to_home_w: solar_to_home_w }
    }.to_json
  end

  def beat_stream(state_json)
    <<~HTML
      <turbo-stream action="replace" target="energy_flow_state"><template><div id="energy_flow_state" hidden data-energy-flow-target="state" data-live-freshness-target="beat" data-state='#{state_json}'></div></template></turbo-stream>
    HTML
  end

  # A <turbo-stream> element executes on DOM insertion — the same path a cable
  # delivery takes, without needing a live broadcast in the test.
  def inject_stream(html)
    page.execute_script("document.body.insertAdjacentHTML('beforeend', arguments[0])", html)
  end

  def skip_ahead_ten_minutes
    page.execute_script(<<~JS)
      const realNow = Date.now
      Date.now = () => realNow() + 10 * 60 * 1000
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS
  end

  def mark_dots
    page.execute_script(<<~JS)
      document.querySelectorAll("[data-ef='efDotsSolarHome'] circle")
              .forEach((dot) => { dot.__mark = "kept" })
    JS
  end

  def dots_survived?
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll("[data-ef='efDotsSolarHome'] circle")]
        .every((dot) => dot.__mark === "kept")
    JS
  end

  def dot_playback_rate
    page.evaluate_script(<<~JS)
      document.querySelector("[data-ef='efDotsSolarHome'] circle")?.getAnimations()[0]?.playbackRate
    JS
  end

  def wait_for
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        result = yield
        return result if result

        sleep 0.05
      end
    end
  end
end
