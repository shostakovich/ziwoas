require_relative "application_system_test_case"

class DashboardRefreshTest < ApplicationSystemTestCase
  setup do
    Plugs::Sample.delete_all
    SolakonReading.delete_all
    now = Time.now.to_i
    Plugs::Sample.create!(plug_id: "bkw", ts: now - 2, apower_w: -420.0, aenergy_wh: 1000.0)
    Plugs::Sample.create!(plug_id: "fridge", ts: now - 2, apower_w: 80.0, aenergy_wh: 500.0)
  end

  test "a page that comes back after a gap asks for a fresh Live-Bild right away" do
    visit root_path
    assert_selector "[data-dashboard-target='tileConsumption']", text: /\d+ W/

    page.execute_script(<<~JS)
      window.__calls = []
      const realFetch = window.fetch
      window.fetch = (...args) => { window.__calls.push(String(args[0])); return realFetch(...args) }
      const realNow = Date.now
      Date.now = () => realNow() + 10 * 60 * 1000
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS

    assert_equal true, wait_for { page.evaluate_script("window.__calls.includes('/api/today')") }
    calls = page.evaluate_script("window.__calls")
    assert_includes calls, "/api/live"
    assert_includes calls, "/api/today/summary"
  end

  test "a Live-Bild that is no longer kept current is dimmed, not emptied" do
    visit root_path
    assert_selector "[data-dashboard-target='tileConsumption']", text: /\d+ W/
    consumption = find("[data-dashboard-target='tileConsumption']").text

    page.execute_script(<<~JS)
      window.fetch = () => Promise.reject(new Error("offline"))
      const realNow = Date.now
      Date.now = () => realNow() + 10 * 60 * 1000
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS

    assert_selector "[data-controller='dashboard'].live-stale"
    assert_equal consumption, find("[data-dashboard-target='tileConsumption']").text
  end

  test "the Live-Bild stops being dimmed once the connection is back" do
    visit root_path
    assert_selector "[data-dashboard-target='tileConsumption']", text: /\d+ W/

    page.execute_script(<<~JS)
      window.__realFetch = window.fetch
      window.fetch = () => Promise.reject(new Error("offline"))
      const realNow = Date.now
      window.__realNow = realNow
      Date.now = () => realNow() + 10 * 60 * 1000
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS
    assert_selector "[data-controller='dashboard'].live-stale"

    page.execute_script(<<~JS)
      window.fetch = window.__realFetch
      Date.now = window.__realNow
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS

    assert_no_selector "[data-controller='dashboard'].live-stale"
  end

  private

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
