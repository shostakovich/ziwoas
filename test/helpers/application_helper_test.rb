require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  cover "ApplicationHelper#main_navigation"
  cover "ApplicationHelper#current_section?"

  test "marks the tab of the current page" do
    assert_equal [ "PV" ], current_labels("/solakon")
  end

  test "keeps a tab active on its sub pages" do
    assert_equal [ "PV" ], current_labels("/solakon/wirtschaftlichkeit")
    assert_equal [ "Schalten" ], current_labels("/switches/anything")
  end

  test "Home is active only on the root path" do
    assert_equal [ "Home" ], current_labels("/")
    assert_empty current_labels("/lights/UPL1")
  end

  test "a path that merely starts with a tab's name is not its sub page" do
    assert_empty current_labels("/solakonx")
  end

  private

  def current_labels(path)
    request.path_info = path
    main_navigation.select(&:current).map(&:label)
  end
end
