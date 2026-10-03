require_relative "application_system_test_case"

class MobileNavigationTest < ApplicationSystemTestCase
  setup { page.current_window.resize_to(390, 844) }

  test "the tab bar sits fixed at the bottom with all six tabs and marks the current one" do
    visit reports_path

    within "nav[aria-label='Tab-Leiste']" do
      assert_selector "a.nav-link", count: 6
      %w[Home PV Schalten Berichte Wetter Sensoren].each { |label| assert_link label }
      assert_selector "a.nav-link[aria-current='page']", count: 1, text: "Berichte"
    end
    assert_no_selector "nav[aria-label='Hauptnavigation']"

    bar = page.evaluate_script(<<~JS)
      (() => {
        const nav = document.querySelector("nav[aria-label='Tab-Leiste']");
        const rect = nav.getBoundingClientRect();
        return { position: getComputedStyle(nav).position, gap: window.innerHeight - rect.bottom,
                 width: rect.width, viewport: document.documentElement.clientWidth };
      })();
    JS

    assert_equal "fixed", bar.fetch("position")
    assert_in_delta 0, bar.fetch("gap"), 1
    assert_in_delta bar.fetch("viewport"), bar.fetch("width"), 1
  end

  test "the bar keeps its place at the bottom edge while the page scrolls" do
    visit root_path
    resting = tab_bar_top

    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    assert_equal resting, tab_bar_top
  end

  test "the end of the page scrolls clear of the tab bar" do
    visit root_path
    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    overlap = page.evaluate_script(<<~JS)
      (() => {
        const last = [...document.querySelectorAll("#main *")].filter((el) => el.getClientRects().length).at(-1);
        return last.getBoundingClientRect().bottom - document.querySelector("nav[aria-label='Tab-Leiste']").getBoundingClientRect().top;
      })();
    JS

    assert_operator overlap, :<=, 0
  end

  test "the header with the logo and the look toggle stays on top" do
    visit root_path

    within "header.app-header" do
      assert_selector "img[alt='Ziwoas — Startseite']"
      assert_button "Filz-Look"
    end
  end

  test "from lg up the header pills take over and the tab bar goes" do
    page.current_window.resize_to(1280, 900)
    visit weather_path

    within "nav[aria-label='Hauptnavigation']" do
      assert_selector "a.nav-link", count: 6
      assert_selector "a.nav-link.active[aria-current='page']", count: 1, text: "Wetter"
    end
    assert_no_selector "nav[aria-label='Tab-Leiste']"
  end

  private

  def tab_bar_top
    page.evaluate_script("document.querySelector(\"nav[aria-label='Tab-Leiste']\").getBoundingClientRect().top")
  end
end
