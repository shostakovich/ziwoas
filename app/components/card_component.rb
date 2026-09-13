class CardComponent < ApplicationComponent
  def initialize(title: nil, subtitle: nil, classes: nil, as: :section, level: 2, **attributes)
    @title = title
    @subtitle = subtitle
    @classes = classes
    @as = as
    @level = level
    @attributes = attributes
  end

  private

  attr_reader :title, :subtitle, :as, :attributes

  def heading_tag = "h#{@level}"

  def css_classes = [ "chart-card", @classes ].compact.join(" ")
end
