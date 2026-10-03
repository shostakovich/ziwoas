require_relative "application_system_test_case"

class LookToggleTest < ApplicationSystemTestCase
  test "the header toggle switches to the felt look and back, and the choice sticks" do
    visit reports_path
    assert_nil look

    click_button "Filz-Look"

    assert_selector "button.app-look-toggle[aria-pressed='true']"
    assert_equal "felt", look
    assert_current_path reports_path

    visit weather_path
    assert_equal "felt", look

    click_button "Filz-Look"

    assert_selector "button.app-look-toggle[aria-pressed='false']"
    assert_nil look
  end

  test "theme colours resolve tokens to plain rgb and follow the colour scheme" do
    visit root_path

    light = theme_color("--viz-solar")
    assert_match(/\Argb\(\d+, \d+, \d+\)\z/, light)

    emulate_color_scheme("dark")
    assert wait_for { page.evaluate_script("window.__themeChanged === true") }, "onThemeChange never fired"
    dark = theme_color("--viz-solar")

    assert_match(/\Argb\(\d+, \d+, \d+\)\z/, dark)
    assert_not_equal light, dark
    assert_equal "rgba(10, 20, 30, 0.5)", page.evaluate_async_script(<<~JS)
      import("lib/theme_colors").then((m) => arguments[0](m.withAlpha("rgb(10, 20, 30)", 0.5)))
    JS
  ensure
    emulate_color_scheme("light")
  end

  private

  def look
    page.evaluate_script("document.documentElement.dataset.look ?? null")
  end

  def theme_color(name)
    page.evaluate_async_script(<<~JS, name)
      const [name, done] = arguments
      import("lib/theme_colors").then((m) => {
        m.onThemeChange(() => { window.__themeChanged = true })
        done(m.themeColor(name))
      })
    JS
  end

  def wait_for(seconds: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (result = yield)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    result
  end

  def emulate_color_scheme(scheme)
    page.driver.browser.page.command("Emulation.setEmulatedMedia",
                                     features: [ { name: "prefers-color-scheme", value: scheme } ])
  end
end
