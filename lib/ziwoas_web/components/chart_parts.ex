defmodule ZiwoasWeb.Components.ChartParts do
  @moduledoc false
  use ZiwoasWeb, :html

  @frame_classes %{wide: "hidden sm:block", narrow: "sm:hidden"}

  @spec frame_classes(:wide | :narrow) :: String.t()
  def frame_classes(frame), do: Map.fetch!(@frame_classes, frame)

  @spec tooltips?(:wide | :narrow) :: boolean
  def tooltips?(frame), do: frame == :wide

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def keys(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-x-4 gap-y-1", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :gradient, :string, required: true
  attr :from, :string, required: true
  attr :to, :string, required: true

  def ramp_key(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 text-xs tabular-nums" data-key="ramp">
      {@from}<span class="legend-ramp" style={"background: #{@gradient}"}></span>{@to}
    </p>
    """
  end

  def nodata_key(assigns) do
    ~H"""
    <p class="flex items-center gap-1.5 text-xs" data-key="nodata">
      <span class="legend-nodata" aria-hidden="true"></span>keine Daten
    </p>
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
