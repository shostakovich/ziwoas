# One box on a page, with its heading inside it rather than floating above:
# what the box says and what it is called stay together, and the page reads as
# a stack of self-contained things. A section made of several boxes keeps its
# label above the group — there is no single box for it to live in.
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

  # A box inside a labelled group sits one level deeper than a box that is a
  # section of the page in its own right.
  def heading_tag = "h#{@level}"

  def css_classes = [ "chart-card", @classes ].compact.join(" ")
end
