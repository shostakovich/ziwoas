defmodule Ziwoas.Plot do
  @moduledoc """
  The geometry of an SVG chart: a frame with margins mapping two domains onto
  pixels. Geometry is rounded to one decimal (`number/1`, integral values as
  Integers); `x/2` and `y/2` stay raw, so callers calculating on don't round
  twice.

  Domains are `{from, to}` pairs (`to` may be below `from`).
  """

  @enforce_keys [:width, :height, :margins, :x_domain, :y_domain]
  defstruct @enforce_keys

  @type domain :: {number, number}
  @type t :: %__MODULE__{
          width: number,
          height: number,
          margins: %{top: number, right: number, bottom: number, left: number},
          x_domain: domain,
          y_domain: domain
        }

  defmodule Tick do
    @moduledoc false
    defstruct [:value, :at]
  end

  defmodule Rect do
    @moduledoc false
    defstruct [:x, :y, :width, :height]
  end

  defmodule Hit do
    @moduledoc false
    defstruct [:rect, :title]
  end

  defmodule Label do
    @moduledoc false
    defstruct [:x, :y, :text, zero: false]
  end

  defmodule Scale do
    @moduledoc false
    defstruct [:step, :top]
  end

  @spec new(keyword) :: t
  def new(opts) do
    %__MODULE__{
      width: Keyword.fetch!(opts, :width),
      height: Keyword.fetch!(opts, :height),
      margins: Map.new(Keyword.fetch!(opts, :margins)),
      x_domain: Keyword.fetch!(opts, :x),
      y_domain: Keyword.fetch!(opts, :y)
    }
  end

  @doc "Rounded to one decimal; an integral result is an Integer."
  @spec number(number) :: number
  def number(value) when is_integer(value), do: value

  def number(value) when is_float(value) do
    rounded = Float.round(value, 1)
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  @spec round_up(number, number) :: number
  def round_up(value, to), do: ceil(value / to) * to

  @spec round_down(number, number) :: number
  def round_down(value, to), do: floor(value / to) * to

  @doc "The first step that fits `peak` into `max_steps` grid lines, and the top it reaches."
  @spec nice_scale(number, [number], pos_integer) :: Scale.t()
  def nice_scale(peak, steps, max_steps) do
    step =
      Enum.find(steps, &(peak <= &1 * max_steps)) ||
        round_up(peak / max_steps, List.last(steps))

    %Scale{step: step, top: max(round_up(peak, step), step)}
  end

  @spec extent([number]) :: domain
  def extent([]), do: {0, 0}
  def extent(values), do: Enum.min_max(values)

  @doc "Every integer of a domain, ascending; none when `to` is below `from`."
  @spec domain_values(domain) :: [integer]
  def domain_values({from, to}) when from <= to, do: Enum.to_list(from..to//1)
  def domain_values(_domain), do: []

  def view_box(plot), do: "0 0 #{to_s(number(plot.width))} #{to_s(number(plot.height))}"

  def left(plot), do: number(x_from(plot))
  def right(plot), do: number(x_to(plot))
  def top(plot), do: number(y_to(plot))
  def bottom(plot), do: number(y_from(plot))

  @spec x(t, number) :: float
  def x(plot, value), do: x_from(plot) + share(value, plot.x_domain) * (x_to(plot) - x_from(plot))

  @spec y(t, number) :: float
  def y(plot, value), do: y_from(plot) + share(value, plot.y_domain) * (y_to(plot) - y_from(plot))

  def x_ticks(plot, values), do: Enum.map(values, &%Tick{value: &1, at: number(x(plot, &1))})

  def y_ticks(plot, values), do: Enum.map(values, &%Tick{value: &1, at: number(y(plot, &1))})

  def grid_lines(plot, values),
    do: plot |> y_ticks(values) |> Enum.reject(&(&1.value == 0)) |> Enum.map(& &1.at)

  def value_labels(plot, values, gap) do
    for tick <- y_ticks(plot, values) do
      %Label{x: left(plot) - gap, y: tick.at, text: to_s(tick.value), zero: tick.value == 0}
    end
  end

  @doc "Points `[{value, measure}]` as an SVG `points` list."
  def line(plot, points),
    do:
      Enum.map_join(points, " ", fn {value, measure} ->
        "#{to_s(number(x(plot, value)))},#{to_s(number(y(plot, measure)))}"
      end)

  @doc "A step wider than `gap` was never measured; one line would bridge it with a shape no data took."
  def polylines(plot, points, gap \\ 1), do: points |> runs(gap) |> Enum.map(&line(plot, &1))

  def areas(plot, points, gap \\ 1) do
    {foot, _} = plot.y_domain

    for run <- runs(points, gap) do
      {first, _} = hd(run)
      {last, _} = List.last(run)
      line(plot, [{first, foot} | run] ++ [{last, foot}])
    end
  end

  def columns(plot, values) do
    for value <- values do
      from = x(plot, value)
      to = min(x(plot, value + 1), x_to(plot))

      %Rect{
        x: number(from),
        y: top(plot),
        width: number(to - from),
        height: number(y_from(plot) - y_to(plot))
      }
    end
  end

  def hits(plot, values, titles),
    do: plot |> columns(values) |> Enum.zip_with(titles, &%Hit{rect: &1, title: &2})

  @doc "Edges are rounded before the size: rounding corner and size apart leaves hairline slits."
  def rect(plot, {x_from, x_to}, {y_from, y_to}, inset \\ 0) do
    xs = [number(x(plot, x_from)), number(x(plot, x_to))]
    ys = [number(y(plot, y_from)), number(y(plot, y_to))]
    {x_min, x_max} = Enum.min_max(xs)
    {y_min, y_max} = Enum.min_max(ys)

    %Rect{
      x: x_min,
      y: y_min,
      width: number(x_max - x_min - inset),
      height: number(y_max - y_min - inset)
    }
  end

  @doc "A number as SVG text: integers plain, floats in their shortest form."
  @spec to_s(number) :: String.t()
  def to_s(value) when is_integer(value), do: Integer.to_string(value)
  def to_s(value) when is_float(value), do: Float.to_string(value)

  defp x_from(plot), do: plot.margins.left
  defp x_to(plot), do: plot.width - plot.margins.right
  defp y_from(plot), do: plot.height - plot.margins.bottom
  defp y_to(plot), do: plot.margins.top

  defp share(value, {from, to}) do
    span = to - from
    (value - from) / if(span == 0, do: 1.0, else: :erlang.float(span))
  end

  # `slice_when`: a new run wherever the next value lies more than `gap` ahead.
  defp runs([], _gap), do: []

  defp runs([first | rest], gap) do
    rest
    |> Enum.reduce({[first], []}, fn {value, _} = point, {[{previous, _} | _] = run, done} ->
      if value - previous > gap,
        do: {[point], [Enum.reverse(run) | done]},
        else: {[point | run], done}
    end)
    |> then(fn {run, done} -> Enum.reverse([Enum.reverse(run) | done]) end)
  end
end
