require_relative "application_system_test_case"

class SolakonOverviewTest < ApplicationSystemTestCase
  setup do
    Solakon::Reading.delete_all
    Solakon::Snapshot.delete_all
  end

  test "Solakon page is usable on mobile without fresh data" do
    page.current_window.resize_to(390, 844)

    visit solakon_path

    assert_text "PV"
    # Section/tile labels are uppercased via CSS (text-transform), so the
    # browser reports e.g. "ENERGIEFLUSS" — match case-insensitively.
    assert_text(/Energiefluss/i)
    assert_text "Außensteckdose"
    assert_text "Auto-Regelung"
    assert_text(/Batteriegesundheit/i)
    assert_selector "canvas[data-solakon-history-target='canvas']"
    assert_no_text "SOH"
    assert_no_text "Modbus"

    chart_box = page.evaluate_script(<<~JS)
      (() => {
        const canvas = document.querySelector("canvas[data-solakon-history-target='canvas']");
        const rect = canvas.getBoundingClientRect();
        return { width: rect.width, height: rect.height };
      })();
    JS

    assert_operator chart_box.fetch("width"), :>, 250
    assert_operator chart_box.fetch("height"), :>, 180
  end

  test "range switches keep the clicked range active across switches" do
    visit solakon_path

    within("turbo-frame#solakon_history") do
      assert_selector "a.active", text: "Letzte 24 h", count: 1

      click_link "Letzte 7 Tage"
      assert_selector "a.active", text: "Letzte 7 Tage", count: 1
      assert_selector "a.active", count: 1

      click_link "Letzte 30 Tage"
      assert_selector "a.active", text: "Letzte 30 Tage", count: 1
      assert_selector "a.active", count: 1

      click_link "Letzte 24 h"
      assert_selector "a.active", text: "Letzte 24 h", count: 1
      assert_selector "a.active", count: 1
    end
  end

  test "a live resync reloads the frame with the selected range" do
    visit solakon_path

    within("turbo-frame#solakon_history") do
      click_link "Letzte 7 Tage"
      assert_selector "a.active", text: "Letzte 7 Tage", count: 1
    end

    # Mark the current frame content; a reload swaps it out and the mark is gone.
    page.execute_script("document.querySelector('[data-controller=\"solakon-history\"]').dataset.stale = 'yes'")
    assert_selector "[data-controller='solakon-history'][data-stale]"

    page.execute_script("document.dispatchEvent(new CustomEvent('live-freshness:resync'))")

    assert_no_selector "[data-controller='solakon-history'][data-stale]"
    within("turbo-frame#solakon_history") do
      assert_selector "a.active", text: "Letzte 7 Tage", count: 1
      assert_selector "canvas[data-solakon-history-target='canvas']"
    end
  end
end
