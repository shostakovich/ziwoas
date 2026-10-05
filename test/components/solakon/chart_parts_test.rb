require "test_helper"

class Solakon::ChartPartsTest < ViewComponent::TestCase
  cover "Solakon::ChartParts*"

  class Harness < ViewComponent::Base
    include Solakon::ChartParts

    def initialize(markup)
      @markup = markup
    end

    def call = @markup.call(self)
  end

  def markup(&block) = render_inline(Harness.new(block)).to_html

  def parts = Harness.new(nil)

  test "shows the wide frame from a small tablet up and the narrow one on phones only" do
    assert_equal "d-none d-sm-block", parts.frame_classes(:wide)
    assert_equal "d-sm-none", parts.frame_classes(:narrow)
    assert_raises(KeyError) { parts.frame_classes(:square) }
  end

  test "leaves the tooltips to the wide frame" do
    assert parts.tooltips?(:wide)
    assert_not parts.tooltips?(:narrow)
  end

  test "lists a legend's keys in a row, spaced as the chart asks" do
    html = markup { |chart| chart.legend_list("mb-3") { chart.legend_item { "Panel 1" } } }

    assert_equal '<ul class="legend list-unstyled d-flex flex-wrap align-items-center column-gap-3 row-gap-1 small ' \
                 'text-body-secondary mb-3"><li class="legend-item d-inline-flex align-items-center gap-2">Panel 1</li></ul>',
                 html
  end

  test "lays a transparent rectangle with its tooltip over every hit" do
    hits = [ Plot::Hit.new(rect: Plot::Rect.new(x: 48, y: 10, width: 119.5, height: 120), title: "10–11 Uhr · <Ø 300 W>") ]

    assert_equal '<g class="hits"><rect x="48" y="10" width="119.5" height="120"><title>10–11 Uhr · &lt;Ø 300 W&gt;</title></rect></g>',
                 markup { |chart| chart.hit_areas(hits) }
  end

  test "writes the value labels right-aligned, marking the zero" do
    labels = [ Plot::Label.new(x: 44, y: 130, text: "0", zero: true), Plot::Label.new(x: 44, y: 90.5, text: "250") ]

    assert_equal '<text x="44" y="130" text-anchor="end" class="zero">0</text><text x="44" y="90.5" text-anchor="end">250</text>',
                 markup { |chart| chart.value_texts(labels) }
  end
end
