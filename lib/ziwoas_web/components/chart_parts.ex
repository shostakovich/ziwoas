defmodule ZiwoasWeb.Components.ChartParts do
  @moduledoc false
  use ZiwoasWeb, :html

  @frame_classes %{wide: "d-none d-sm-block", narrow: "d-sm-none"}

  @spec frame_classes(:wide | :narrow) :: String.t()
  def frame_classes(frame), do: Map.fetch!(@frame_classes, frame)

  @spec tooltips?(:wide | :narrow) :: boolean
  def tooltips?(frame), do: frame == :wide

  attr :class, :string, required: true
  slot :inner_block, required: true

  def legend_list(assigns) do
    ~H"""
    <ul class={[
      "legend list-unstyled d-flex flex-wrap align-items-center column-gap-3 row-gap-1 small text-body-secondary",
      @class
    ]}>
      {render_slot(@inner_block)}
    </ul>
    """
  end

  slot :inner_block, required: true

  def legend_item(assigns) do
    ~H"""
    <li class="legend-item d-inline-flex align-items-center gap-2">{render_slot(@inner_block)}</li>
    """
  end

  attr :hits, :list, required: true

  def hit_areas(assigns) do
    ~H"""
    <g class="hits">
      <rect
        :for={hit <- @hits}
        x={hit.rect.x}
        y={hit.rect.y}
        width={hit.rect.width}
        height={hit.rect.height}
      >
        <title>{hit.title}</title>
      </rect>
    </g>
    """
  end

  attr :labels, :list, required: true

  def value_texts(assigns) do
    ~H"""
    <text
      :for={label <- @labels}
      x={label.x}
      y={label.y}
      text-anchor="end"
      {if label.zero, do: [class: "zero"], else: []}
    >
      {label.text}
    </text>
    """
  end
end
