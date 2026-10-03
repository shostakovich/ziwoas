require "test_helper"

class LookTest < ActiveSupport::TestCase
  cover "Look*"

  test "knows the two looks and reads anything else as Clean" do
    assert_equal "felt", Look.named("felt")
    assert_equal "clean", Look.named("clean")
    assert_equal "clean", Look.named("neon")
    assert_equal "clean", Look.named(nil)
  end

  test "gives each look the page background of both colour schemes" do
    assert_equal({ light: "#f6f7f9", dark: "#212529" }, Look.theme_colors("clean"))
    assert_equal({ light: "#e7dccb", dark: "#242220" }, Look.theme_colors("felt"))
  end
end
