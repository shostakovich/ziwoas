require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  cover "ApplicationHelper#main_navigation"
  cover "ApplicationHelper#current_section?"
  cover "ApplicationHelper#ui_icon"
  cover "ApplicationHelper#de_number"

  test "marks the tab of the current page" do
    assert_equal [ "PV" ], current_labels("/solakon")
  end

  test "keeps a tab active on its sub pages" do
    assert_equal [ "PV" ], current_labels("/solakon/wirtschaftlichkeit")
    assert_equal [ "Schalten" ], current_labels("/switches/anything")
  end

  test "Home is active only on the root path" do
    assert_equal [ "Home" ], current_labels("/")
    assert_empty current_labels("/up")
  end

  test "a lamp's page belongs to the Schalten tab it is reached from" do
    assert_equal [ "Schalten" ], current_labels("/lights/UPL1")
    assert_equal [ "Schalten" ], current_labels("/lights/UPL1/edit")
    assert_empty current_labels("/lightsx")
  end

  test "a path that merely starts with a tab's name is not its sub page" do
    assert_empty current_labels("/solakonx")
  end

  test "draws an action glyph in the text colour, hidden from screen readers" do
    svg = Nokogiri::HTML5.fragment(ui_icon(:pause)).at_css("svg")

    assert_equal [ "pause", "currentColor", "true", "0 0 16 16" ], [ svg["data-icon"], svg["fill"], svg["aria-hidden"], svg["viewBox"] ]
    assert_equal ApplicationHelper::UI_ICONS.fetch(:pause), svg.at_css("path")["d"]
    assert_raises(KeyError) { ui_icon(:unknown) }
  end

  test "draws the glyph at its own 16 pixels, out of the tab order" do
    svg = Nokogiri::HTML5.fragment(ui_icon(:edit)).at_css("svg")

    assert_equal [ "16", "16", "false" ], [ svg["width"], svg["height"], svg["focusable"] ]
  end

  test "formats a number the German way, whole by default" do
    assert_equal "−1.235", de_number(-1234.5)
    assert_equal "2,50", de_number(2.5, precision: 2)
  end

  test "passes the unit through, and writes a missing value as a dash" do
    assert_equal "2,5 kWh", de_number(2.5, precision: 1, unit: "kWh")
    assert_equal "— W", de_number(nil, unit: "W")
  end

  private

  def current_labels(path)
    request.path_info = path
    main_navigation.select(&:current).map(&:label)
  end
end
