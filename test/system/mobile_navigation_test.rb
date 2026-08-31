require_relative "application_system_test_case"

class MobileNavigationTest < ApplicationSystemTestCase
  test "mobile navigation is fixed at the bottom with all primary links" do
    page.current_window.resize_to(390, 844)

    visit root_path

    within "nav.app-nav" do
      assert_text "Home"
      assert_text "PV"
      assert_text "Schalten"
      assert_text "Berichte"
      assert_text "Wetter"
      assert_text "Sensoren"
    end

    nav_box = page.evaluate_script(<<~JS)
      (() => {
      const nav = document.querySelector('nav.app-nav');
      const rect = nav.getBoundingClientRect();
      const styles = window.getComputedStyle(nav);
      return { position: styles.position, bottom: window.innerHeight - rect.bottom, columns: styles.gridTemplateColumns.split(' ').length };
      })();
    JS

    assert_equal "fixed", nav_box.fetch("position")
    assert_operator nav_box.fetch("bottom"), :<, 40
    assert_equal 6, nav_box.fetch("columns")
  end

  test "the bar keeps its place at the bottom edge while the page scrolls" do
    page.current_window.resize_to(390, 844)

    visit root_path
    resting = nav_viewport_top

    page.execute_script("window.scrollTo(0, document.body.scrollHeight)")

    assert_equal resting, nav_viewport_top
  end

  test "the glass sits on the pane behind the bar, never on the fixed bar itself" do
    page.current_window.resize_to(390, 844)

    visit root_path

    glass = page.evaluate_script(<<~JS)
      (() => {
      const nav = document.querySelector('nav.app-nav');
      const read = (el) => window.getComputedStyle(el).backdropFilter ||
                           window.getComputedStyle(el).webkitBackdropFilter;
      return { bar: read(nav), pane: window.getComputedStyle(nav, '::before').backdropFilter };
      })();
    JS

    assert_equal "none", glass.fetch("bar")
    assert_includes glass.fetch("pane"), "blur"
  end

  private

  def nav_viewport_top
    page.evaluate_script("document.querySelector('nav.app-nav').getBoundingClientRect().top")
  end
end
