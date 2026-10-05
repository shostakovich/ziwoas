require "test_helper"

class Lights::ScenesComponentTest < ViewComponent::TestCase
  cover "Lights::ScenesComponent*"

  def previews(*names)
    light = Light.new(key: "K1", name: "Lampe", firmware_scenes: names)
    render_inline(Lights::ScenesComponent.new(light: light)).css("span.ld-scene-preview").map { |n| n["style"] }
  end

  test "lists firmware scenes with a deterministic gradient preview" do
    light = Light.new(key: "K1", name: "Lampe", firmware_scenes: %w[Forest Aurora])
    rendered = render_inline(Lights::ScenesComponent.new(light: light))

    assert_includes rendered.to_html, "Govee-Szenen"
    assert_equal 2, rendered.css("form input[name=effect]").length
    assert_includes rendered.to_html, "Forest"
    previews = rendered.css("span.ld-scene-preview").map { |n| n["style"] }
    assert previews.all? { |s| s.include?("linear-gradient") }
    refute_equal previews[0], previews[1]
  end

  test "shows an empty-state hint when there are no scenes" do
    light = Light.new(key: "K2", name: "Lampe", firmware_scenes: [])
    rendered = render_inline(Lights::ScenesComponent.new(light: light))

    assert rendered.css("form input[name=effect]").none?
    assert_includes rendered.to_html, "Diese Lampe meldet keine Govee-Szenen."
  end

  test "scene names that say how they look get a matching palette" do
    ocean, sunset, forest, candle, party, aurora = previews("Ocean", "Sunset", "Forest", "Candlelight", "Party", "Aurora")
    assert_equal "background-image: linear-gradient(135deg, hsl(195 80% 50%), hsl(225 70% 40%))", ocean
    assert_includes sunset, "hsl(32 95% 58%), hsl(335 75% 58%)"
    assert_includes forest, "hsl(105 50% 48%), hsl(150 55% 30%)"
    assert_includes candle, "hsl(40 95% 58%), hsl(20 90% 45%)"
    assert_equal 5, party.scan("hsl(").size, "party is vivid and many-coloured"
    assert_includes aurora, "hsl(150 70% 45%), hsl(175 70% 42%), hsl(270 55% 55%)"
  end

  test "keywords match case-insensitively, in German too, and the first one wins" do
    assert_equal previews("Ocean"), previews("DEEP OCEAN")
    assert_equal previews("Romantic"), previews("Romantik")
    assert_equal previews("Reading"), previews("Lesen")
    assert_equal previews("Aurora"), previews("Aurora Party"), "aurora is listed before party"
  end

  test "short keywords only match whole words" do
    refute_equal previews("Ice"), previews("Rice Field")
    refute_equal previews("Starry"), previews("Start")
  end

  test "names without a keyword fall back to a stable hash of the name" do
    first, second = previews("Zauberwürfel", "Zauberwürfel")
    assert_equal first, second
    sum = "zauberwürfel".each_char.sum(&:ord) # code points, not bytes: ü counts once
    assert_equal "background-image: linear-gradient(135deg, hsl(#{sum % 360} 70% 55%), hsl(#{(sum * 7) % 360} 65% 45%))", first
  end
end
