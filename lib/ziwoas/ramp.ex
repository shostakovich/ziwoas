defmodule Ziwoas.Ramp do
  @moduledoc """
  A colour ramp over CSS tokens. Colours between stops are
  `color-mix()`, so the browser resolves them and dark mode follows.
  """
  @stops %{
    amber: ~w[var(--ramp-amber-0) var(--ramp-amber-1) var(--ramp-amber-2)],
    blue: ~w[var(--ramp-blue-0) var(--ramp-blue-1) var(--ramp-blue-2)],
    grey: ~w[var(--ramp-grey-0) var(--ramp-grey-1)],
    diverging: ~w[var(--ramp-low) var(--ramp-neutral) var(--ramp-high)]
  }

  # Snapping to levels lets near-equal values share one fill; a step is below what the eye tells apart.
  @levels 64

  @enforce_keys [:stops]
  defstruct @enforce_keys

  @type t :: %__MODULE__{stops: [String.t()]}

  @spec new([String.t()]) :: t
  def new(stops), do: %__MODULE__{stops: stops}

  @spec names() :: [atom]
  def names, do: [:amber, :blue, :grey, :diverging]

  @spec fetch(atom) :: t
  def fetch(name), do: %__MODULE__{stops: Map.fetch!(@stops, name)}

  @spec level(number) :: float
  def level(fraction), do: Kernel.round(fraction * @levels) / @levels

  @spec color(t, number) :: String.t()
  def color(%__MODULE__{stops: stops}, fraction) do
    position = clamp(fraction) * (length(stops) - 1)
    index = min(floor(position), length(stops) - 2)
    mix(Enum.at(stops, index), Enum.at(stops, index + 1), position - index)
  end

  @spec css_gradient(t) :: String.t()
  def css_gradient(%__MODULE__{stops: stops}),
    do: "linear-gradient(90deg, #{Enum.join(stops, ", ")})"

  defp clamp(fraction), do: fraction |> max(0.0) |> min(1.0) |> :erlang.float()

  defp mix(from, to, share) do
    percent = Float.round(share * 100, 1)

    cond do
      percent == 0 -> from
      percent == 100 -> to
      true -> "color-mix(in oklab, #{to} #{percent_text(percent)}%, #{from})"
    end
  end

  defp percent_text(percent) when percent == trunc(percent), do: Integer.to_string(trunc(percent))
  defp percent_text(percent), do: Float.to_string(percent)
end
