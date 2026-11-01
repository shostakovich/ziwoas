defmodule Ziwoas.Hue.ColorTest do
  use ExUnit.Case, async: true

  alias Ziwoas.Hue.Color

  @gamut_c {{0.6915, 0.3083}, {0.17, 0.7}, {0.1532, 0.0475}}

  defp close?({ax, ay}, {bx, by}), do: abs(ax - bx) < 0.002 and abs(ay - by) < 0.002

  test "white and the primaries land where Philips puts them" do
    assert close?(Color.to_xy(%{r: 255, g: 255, b: 255}, nil), {0.3227, 0.329})
    assert close?(Color.to_xy(%{r: 255, g: 0, b: 0}, nil), {0.7006, 0.2993})
    assert close?(Color.to_xy(%{r: 0, g: 0, b: 255}, nil), {0.1355, 0.0399})
  end

  test "black has no colour and becomes white" do
    assert Color.to_xy(%{r: 0, g: 0, b: 0}, @gamut_c) == {0.3127, 0.329}
  end

  test "a colour outside the gamut moves to its nearest edge, one inside stays" do
    assert close?(Color.to_xy(%{r: 255, g: 0, b: 0}, @gamut_c), {0.6915, 0.3083})
    assert Color.into_gamut({0.4, 0.4}, @gamut_c) == {0.4, 0.4}
    assert close?(Color.into_gamut({0.1, 0.4}, @gamut_c), {0.1611, 0.3995})
  end

  test "xy back to RGB at full brightness" do
    assert Color.to_rgb({0.3227, 0.329}) == %{r: 255, g: 255, b: 255}
    assert %{r: 255, g: g, b: b} = Color.to_rgb({0.7006, 0.2993})
    assert g < 10 and b < 10
    assert Color.to_rgb({0.3, 0.0}) == %{r: 255, g: 255, b: 255}
  end

  test "kelvin and mirek, clamped into the lamp's range" do
    assert Color.mirek(2700, {153, 454}) == 370
    assert Color.mirek(1000, {153, 454}) == 454
    assert Color.mirek(10_000, {153, 454}) == 153
    assert Color.kelvin(370) == 2703
  end
end
