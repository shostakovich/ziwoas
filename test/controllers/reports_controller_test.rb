require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  cover "ApplicationHelper#main_navigation"

  # AggregatorJobTest runs without a transaction, so its rows can reach this class.
  setup do
    Plugs::DailyTotal.delete_all
    DailyEnergySummary.delete_all
  end

  test "reports page renders" do
    get "/reports"

    assert_response :success
    assert_select "h1", text: "Berichte", count: 1
    assert_select "section[aria-label='Zeitraum']", 1
  end

  test "reports page accepts custom range params" do
    get "/reports", params: { start_date: "2026-04-01", end_date: "2026-04-07" }

    assert_response :success
    assert_select "input[name='start_date'][value='2026-04-01']"
    assert_select "input[name='end_date'][value='2026-04-07']"
  end

  test "a custom range marks Benutzerdefiniert, not a preset, as active" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)

    get "/reports", params: { start_date: "2026-04-01", end_date: "2026-04-07" }

    assert_select ".btn-group[aria-label='Schnellauswahl'] .btn.active", text: "Benutzerdefiniert", count: 1
    assert_select ".btn-group[aria-label='Schnellauswahl'] a[aria-current]", 0
  end

  test "the active preset is marked as the current page" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)

    get "/reports", params: { preset: "last_30" }

    assert_select ".btn-group[aria-label='Schnellauswahl'] a.btn", 2
    assert_select ".btn-group[aria-label='Schnellauswahl'] a.btn.active[aria-current='page']", text: "Letzte 30 Tage", count: 1
    assert_select ".btn-group[aria-label='Schnellauswahl'] .btn.active", 1
  end

  test "the date form labels its fields and submits without a commit param" do
    get "/reports"

    assert_select "form[action='/reports'][method='get']" do
      assert_select "label.form-label[for='start_date']", text: "Von"
      assert_select "label.form-label[for='end_date']", text: "Bis"
      assert_select "input.form-control#start_date[type='date']", 1
      assert_select "input.form-control#end_date[type='date']", 1
      assert_select "input[type='submit'][value='Anwenden']:not([name])", 1
    end
  end

  test "an invalid range is reported as a warning" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)

    get "/reports", params: { start_date: "2026-04-07", end_date: "2026-04-01" }

    assert_select ".alert.alert-warning", text: /ungueltig/
  end

  test "reports page renders summary ranking and chart payload" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)

    get "/reports"

    assert_response :success
    assert_select "section[aria-label='Zusammenfassung'] .stat", 8
    labels = css_select("section[aria-label='Zusammenfassung'] .stat-label").map { |node| node.text.squish }
    assert_equal [ "Ertrag", "Verbrauch", "Gespart", "Bilanz", "Autarkie", "Eigen\u00ADverbrauchs\u00ADquote", "Ø Ertrag/Tag", "Ø Verbrauch/Tag" ], labels
    assert_select "main h2", text: "Zeitraum", count: 0
    assert_select "main h2", text: "Zusammenfassung", count: 0
    assert_select "main h2", text: "Steckdosen"
    assert_select ".card-title", text: "Energie"
    assert_select ".card-subtitle", text: "Ertrag / Verbrauch"
    assert_select ".card-title", text: "Leistung"
    assert_select ".card .chart-frame", minimum: 2
    assert_select "ul.list-group[aria-label='Erzeugung'] > li.list-group-item", 1
    assert_select "[data-energy-report-target='dailyCanvas']", 1
    assert_select "[data-energy-report-target='detailCanvas']", 1
    assert_select "script[data-energy-report-target='payload']", 1
  end

  test "the producer stands apart from the numbered consumers, each bar in its dashboard colour" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)
    Plugs::DailyTotal.create!(plug_id: "fridge", date: "2026-04-10", energy_wh: 500)

    get "/reports"

    assert_select "ul.list-group[aria-label='Erzeugung'] > li[data-plug-id='bkw']", 1 do
      assert_select "img[alt='Erzeuger']", 1
      assert_select ".progress-bar[style*='width: 100.0%'][style*='var(--viz-solar)']", 1
    end
    assert_select "ol.list-group[aria-label='Rangliste'] > li", 1
    assert_select "ol.list-group[aria-label='Rangliste'] > li[data-plug-id='fridge']", 1 do
      assert_select ".col-1", text: "1"
      assert_select ".progress-bar[style*='width: 25.0%'][style*='var(--viz-1)']", 1
      assert_select ".text-end", text: "0,50 kWh"
      # On phones the bar takes a line of its own below the name.
      assert_select ".order-last.order-sm-0 > .progress", 1
    end
  end

  test "reports page orders widgets like the dashboard" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)

    get "/reports"

    headings = css_select("main h2").map { |node| node.text.squish }
    assert_equal "Steckdosen", headings[0]
    assert_match(/\AEnergie/, headings[1])
    assert_match(/\ALeistung/, headings[2])
    assert_match(/\AAutarkie/, headings[3])
  end

  test "reports page describes the power chart resolution" do
    30.times do |i|
      Plugs::DailyTotal.create!(plug_id: "bkw", date: (Date.new(2026, 4, 1) + i).to_s, energy_wh: 2000)
    end

    get "/reports", params: { preset: "last_30" }

    assert_response :success
    assert_select ".card-title", text: "Leistung"
    assert_select ".card-subtitle", text: /\ATagesmittel · /
  end

  test "reports page shows empty state without data" do
    get "/reports"

    assert_response :success
    assert_select ".empty-state", text: /Noch keine Berichtsdaten/
  end

  test "layout includes accessible navigation labels and decorative plush icons" do
    get "/reports"

    assert_response :success
    assert_no_match %r{href="/app\.css}, response.body
    assert_select "link[rel='stylesheet'][href='https://felt-css.rocu.de/felt.css']:not([data-turbo-track])", 1
    assert_select "link[href^='/assets/application'][data-turbo-track='reload']", 1
    assert_select "header.app-header", 1
    assert_select ".app-header .navbar-brand picture", 1 do
      assert_select "source[media='(prefers-color-scheme: dark)'][srcset*='logo-dark']", 1
      assert_select "img[alt='Ziwoas — Startseite'][src*='logo']", 1
    end

    expected_links = {
      root_path => [ "Home", "nav_dashboard_plush.webp" ],
      solakon_path => [ "PV", "nav_pv_plush.webp" ],
      switches_path => [ "Schalten", "nav_switches_plush.webp" ],
      reports_path => [ "Berichte", "nav_reports_plush.webp" ],
      weather_path => [ "Wetter", "nav_weather_plush.webp" ],
      sensors_path => [ "Sensoren", "nav_sensors_plush.webp" ]
    }

    # The same six tabs twice: header pills from lg up, the tab bar below.
    [ "Hauptnavigation", "Tab-Leiste" ].each do |nav_label|
      assert_select "nav[aria-label='#{nav_label}'] a.nav-link", 6
      expected_links.each do |path, (label, icon)|
        # Propshaft digests asset filenames (nav_dashboard_plush-<digest>.webp),
        # so match the digest-tolerant basename rather than the literal filename.
        icon_basename = File.basename(icon, ".webp")
        assert_select "nav[aria-label='#{nav_label}'] a.nav-link[href='#{path}']", text: label, count: 1 do
          assert_select "img[alt=''][aria-hidden='true'][src*='#{icon_basename}']", count: 1
        end
      end
      assert_select "nav[aria-label='#{nav_label}'] a.nav-link.active[aria-current='page'][href='#{reports_path}']", 1
      assert_select "nav[aria-label='#{nav_label}'] a.nav-link[aria-current]", 1
    end

    assert_select "nav.navbar.fixed-bottom.pb-safe.d-lg-none[aria-label='Tab-Leiste'] ul.nav.nav-pills.nav-fill"
    assert_select "nav.d-none.d-lg-block[aria-label='Hauptnavigation']"
    assert_select "a.visually-hidden-focusable[href='#main']", text: "Zum Inhalt springen"
    assert_select "main#main.container", 1

    get root_path
    expected_links.each_key { |path| assert_select "a.nav-link[href='#{path}']", 2 }
  end

  test "reports page renders Autarkie & Eigenverbrauchsquote section" do
    Plugs::DailyTotal.create!(plug_id: "bkw", date: "2026-04-10", energy_wh: 2000)
    DailyEnergySummary.create!(date: "2026-04-10", produced_wh: 2000.0, consumed_wh: 1000.0, self_consumed_wh: 500.0)

    get "/reports"

    assert_response :success
    assert_select ".card-title", text: "Autarkie & Eigenverbrauchsquote"
    assert_select "[data-energy-report-target='ratiosCanvas']", 1
  end
end
