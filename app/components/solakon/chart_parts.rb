module Solakon
  module ChartParts
    FRAME_CLASSES = { wide: "d-none d-sm-block", narrow: "d-sm-none" }.freeze
    LEGEND_CLASSES = %w[legend list-unstyled d-flex flex-wrap align-items-center column-gap-3 row-gap-1 small
                        text-body-secondary].freeze
    LEGEND_ITEM_CLASSES = %w[legend-item d-inline-flex align-items-center gap-2].freeze

    def frame_classes(frame) = FRAME_CLASSES.fetch(frame)

    # A phone shows no SVG tooltips.
    def tooltips?(frame) = frame == :wide

    def legend_list(spacing, &) = tag.ul(class: [ LEGEND_CLASSES, spacing ], &)

    def legend_item(&) = tag.li(class: LEGEND_ITEM_CLASSES, &)

    def hit_areas(hits)
      tag.g(class: "hits") { safe_join(hits.map { |hit| tag.rect(**hit.rect.to_h) { tag.title(hit.title) } }) }
    end

    def value_texts(labels)
      safe_join(labels.map do |label|
        tag.text(label.text, x: label.x, y: label.y, "text-anchor": "end", class: ("zero" if label.zero))
      end)
    end
  end
end
