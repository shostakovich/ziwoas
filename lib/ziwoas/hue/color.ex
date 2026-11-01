defmodule Ziwoas.Hue.Color do
  @moduledoc "sRGB to CIE xy and back with the wide-gamut matrix Philips documents for Hue."

  @type xy :: {float, float}
  @type gamut :: {xy, xy, xy}
  @type rgb :: %{r: 0..255, g: 0..255, b: 0..255}

  @white {0.3127, 0.329}

  @doc "Black has no chromaticity and becomes white."
  @spec to_xy(rgb, gamut | nil) :: xy
  def to_xy(%{r: r, g: g, b: b}, gamut) do
    {r, g, b} = {linear(r), linear(g), linear(b)}
    x = r * 0.664511 + g * 0.154324 + b * 0.162028
    y = r * 0.283881 + g * 0.668433 + b * 0.047685
    z = r * 0.000088 + g * 0.072310 + b * 0.986039
    sum = x + y + z

    if sum == 0, do: @white, else: into_gamut({x / sum, y / sum}, gamut)
  end

  @doc "At full brightness: the colour a lamp shows, not how bright it is."
  @spec to_rgb(xy) :: rgb
  def to_rgb({_x, y}) when y <= 0, do: %{r: 255, g: 255, b: 255}

  def to_rgb({x, y}) do
    big_x = x / y
    big_z = (1 - x - y) / y

    linear = [
      big_x * 1.656492 - 0.354851 - big_z * 0.255038,
      -big_x * 0.707196 + 1.655397 + big_z * 0.036152,
      big_x * 0.051713 - 0.121364 + big_z * 1.011530
    ]

    peak = linear |> Enum.max() |> max(1.0e-9)
    [r, g, b] = Enum.map(linear, &(&1 |> max(0.0) |> Kernel./(peak) |> gamma()))
    %{r: r, g: g, b: b}
  end

  @spec mirek(pos_integer, {pos_integer, pos_integer}) :: pos_integer
  def mirek(kelvin, {lowest, highest}),
    do: round(1_000_000 / kelvin) |> max(lowest) |> min(highest)

  @spec kelvin(pos_integer) :: pos_integer
  def kelvin(mirek), do: round(1_000_000 / mirek)

  defp linear(byte) do
    value = byte / 255
    if value > 0.04045, do: :math.pow((value + 0.055) / 1.055, 2.4), else: value / 12.92
  end

  defp gamma(value) do
    value =
      if value <= 0.0031308, do: 12.92 * value, else: 1.055 * :math.pow(value, 1 / 2.4) - 0.055

    value |> Kernel.*(255) |> round() |> max(0) |> min(255)
  end

  @spec into_gamut(xy, gamut | nil) :: xy
  def into_gamut(point, nil), do: point

  def into_gamut(point, {red, green, blue} = gamut) do
    if inside?(point, gamut),
      do: point,
      else:
        [{red, green}, {green, blue}, {blue, red}]
        |> Enum.map(fn {a, b} -> closest_on_segment(point, a, b) end)
        |> Enum.min_by(&distance(&1, point))
  end

  defp inside?(point, {a, b, c}) do
    signs = [cross(a, b, point), cross(b, c, point), cross(c, a, point)]
    Enum.all?(signs, &(&1 >= 0)) or Enum.all?(signs, &(&1 <= 0))
  end

  defp cross({ax, ay}, {bx, by}, {px, py}), do: (bx - ax) * (py - ay) - (by - ay) * (px - ax)

  defp closest_on_segment(_point, a, a), do: a

  defp closest_on_segment({px, py}, {ax, ay}, {bx, by}) do
    {dx, dy} = {bx - ax, by - ay}
    t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)) |> max(0.0) |> min(1.0)
    {ax + t * dx, ay + t * dy}
  end

  defp distance({ax, ay}, {bx, by}), do: :math.sqrt((ax - bx) ** 2 + (ay - by) ** 2)
end
