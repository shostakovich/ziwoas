require_relative "application_system_test_case"

# A browser abroad still labels chart axes on the household's clock
# (Europe/Berlin in config/ziwoas.test.yml).
class ChartTimeZoneTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.page.command("Emulation.setTimezoneOverride", timezoneId: "America/New_York")
    visit root_path
  end

  teardown do
    page.driver.browser.page.command("Emulation.setTimezoneOverride", timezoneId: "")
  end

  test "the layout names the household zone, not the browser's" do
    assert_selector "meta[name='ziwoas-time-zone'][content='Europe/Berlin']", visible: false
    assert_equal "America/New_York", page.evaluate_script("Intl.DateTimeFormat().resolvedOptions().timeZone")
    assert_equal "Europe/Berlin", chart_theme("m.timeZone")
  end

  test "a day ticks every three household hours, also across the autumn clock change" do
    ticks = chart_theme(<<~JS)
      (() => {
        const min = m.localMidnight("2026-10-25"), max = m.localMidnight("2026-10-26")
        const scale = m.timeScale(min, max)
        return m.timeTicks(min, max).map((t) => [ new Date(t).toISOString(), scale.ticks.callback.call({ min, max }, t) ])
      })()
    JS

    assert_equal [
      [ "2026-10-24T22:00:00.000Z", "00:00" ],
      [ "2026-10-25T02:00:00.000Z", "03:00" ],
      [ "2026-10-25T05:00:00.000Z", "06:00" ],
      [ "2026-10-25T08:00:00.000Z", "09:00" ],
      [ "2026-10-25T11:00:00.000Z", "12:00" ],
      [ "2026-10-25T14:00:00.000Z", "15:00" ],
      [ "2026-10-25T17:00:00.000Z", "18:00" ],
      [ "2026-10-25T20:00:00.000Z", "21:00" ],
      [ "2026-10-25T23:00:00.000Z", "00:00" ]
    ], ticks
  end

  test "longer spans tick on household midnights with household dates" do
    ticks = chart_theme(<<~JS)
      (() => {
        const min = m.localMidnight("2026-10-23"), max = m.localMidnight("2026-10-27") + 3_600_000
        const scale = m.timeScale(min, max)
        return m.timeTicks(min, max).map((t) => [ new Date(t).toISOString(), scale.ticks.callback.call({ min, max }, t) ])
      })()
    JS

    assert_equal [
      [ "2026-10-22T22:00:00.000Z", "Fr 23.10." ],
      [ "2026-10-23T22:00:00.000Z", "Sa 24.10." ],
      [ "2026-10-24T22:00:00.000Z", "So 25.10." ],
      [ "2026-10-25T23:00:00.000Z", "Mo 26.10." ],
      [ "2026-10-26T23:00:00.000Z", "Di 27.10." ]
    ], ticks
  end

  test "category axes and tooltips use the household clock" do
    labels = chart_theme(<<~JS)
      (() => {
        const times = [ Date.UTC(2026, 9, 4, 10), Date.UTC(2026, 9, 4, 13), Date.UTC(2026, 9, 4, 16) ]
        const scale = m.timeCategoryScale(times)
        return [ 0, 1, 2 ].map((i) => scale.ticks.callback(i))
      })()
    JS

    assert_equal [ "12:00", "15:00", "18:00" ], labels
    assert_equal "So., 14:05",
                 chart_theme('m.formatTime(Date.UTC(2026, 9, 4, 12, 5), { weekday: "short", hour: "2-digit", minute: "2-digit" })')
  end

  private

  def chart_theme(expression)
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      import("lib/chart_theme").then((m) => done(#{expression}))
    JS
  end
end
