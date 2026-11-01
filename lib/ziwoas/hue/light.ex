defmodule Ziwoas.Hue.Light do
  @moduledoc "One `light` resource of the bridge: the lamp it is, its state and its updates."
  alias Ziwoas.Hue.Color

  @type resource :: map

  @no_effect "no_effect"

  @doc "A lamp is keyed by its light service, so each light source of a device is a lamp."
  @spec key(String.t()) :: String.t()
  def key(id), do: String.replace(id, "-", "")

  @spec id(String.t()) :: String.t()
  def id(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>),
    do: Enum.join([a, b, c, d, e], "-")

  def id(key), do: key

  @spec lamp(resource, String.t()) :: map
  def lamp(light, name) do
    {min_k, max_k} = kelvin_range(light)

    %{
      key: key(light["id"]),
      vendor: :hue,
      name: name,
      supports_color: is_map(light["color"]),
      supports_color_temp: min_k != nil,
      color_temp_min_k: min_k,
      color_temp_max_k: max_k,
      scenes: effects(light)
    }
  end

  @doc "A lamp the bridge cannot reach is never on, whatever the bridge remembers."
  @spec state(resource, boolean) :: map
  def state(light, reachable) do
    %{on: reachable and match?(%{"on" => %{"on" => true}}, light), reachable: reachable}
    |> put_brightness(light)
    |> put_colour(light)
  end

  @spec update(resource, Ziwoas.Lights.Bridge.verb()) :: {:ok, map} | {:error, :unsupported}
  def update(_light, {:power, on}), do: {:ok, %{"on" => %{"on" => on}}}

  def update(%{"dimming" => %{}}, {:brightness, value}),
    do: {:ok, %{"on" => %{"on" => true}, "dimming" => %{"brightness" => value}}}

  def update(%{"color" => color}, {:color, rgb}) do
    {x, y} = Color.to_xy(rgb, gamut(color))
    {:ok, %{"on" => %{"on" => true}, "color" => %{"xy" => %{"x" => round4(x), "y" => round4(y)}}}}
  end

  def update(light, {:color_temp, kelvin}) do
    with {:ok, range} <- mirek_range(light) do
      mirek = Color.mirek(kelvin, range)
      {:ok, %{"on" => %{"on" => true}, "color_temperature" => %{"mirek" => mirek}}}
    end
  end

  def update(light, {:scene, effect}) do
    if effect in effects(light),
      do: {:ok, effect_update(light, effect)},
      else: {:error, :unsupported}
  end

  def update(_light, _verb), do: {:error, :unsupported}

  defp effect_update(light, effect) do
    update =
      if Map.has_key?(light, "effects_v2"),
        do: %{"effects_v2" => %{"action" => %{"effect" => effect}}},
        else: %{"effects" => %{"effect" => effect}}

    if effect == @no_effect, do: update, else: Map.put(update, "on", %{"on" => true})
  end

  @doc "Starts with the way back to plain light, unless there is no effect to leave."
  @spec effects(resource) :: [String.t()]
  def effects(light) do
    values =
      case light do
        %{"effects_v2" => %{"action" => %{"effect_values" => values}}} when is_list(values) ->
          values

        %{"effects" => %{"effect_values" => values}} when is_list(values) ->
          values

        _light ->
          []
      end

    case values |> Enum.filter(&is_binary/1) |> List.delete(@no_effect) do
      [] -> []
      effects -> [@no_effect | effects]
    end
  end

  defp kelvin_range(light) do
    case mirek_range(light) do
      {:ok, {lowest, highest}} -> {Color.kelvin(highest), Color.kelvin(lowest)}
      {:error, :unsupported} -> {nil, nil}
    end
  end

  defp mirek_range(%{
         "color_temperature" => %{
           "mirek_schema" => %{"mirek_minimum" => lowest, "mirek_maximum" => highest}
         }
       })
       when is_integer(lowest) and is_integer(highest) and 0 < lowest and lowest <= highest,
       do: {:ok, {lowest, highest}}

  defp mirek_range(_light), do: {:error, :unsupported}

  defp put_brightness(state, %{"dimming" => %{"brightness" => brightness}})
       when is_number(brightness),
       do: Map.put(state, :brightness, brightness |> round() |> max(1))

  defp put_brightness(state, _light), do: state

  defp put_colour(state, %{"color_temperature" => %{"mirek_valid" => true, "mirek" => mirek}})
       when is_integer(mirek) and mirek > 0,
       do: Map.put(state, :color_temp_k, Color.kelvin(mirek))

  defp put_colour(state, %{"color" => %{"xy" => %{"x" => x, "y" => y}}})
       when is_number(x) and is_number(y),
       do: Map.merge(state, %{color_temp_k: nil, color: Color.to_rgb({x, y})})

  defp put_colour(state, _light), do: state

  defp gamut(%{"gamut" => %{"red" => red, "green" => green, "blue" => blue}}) do
    corners = Enum.map([red, green, blue], &point/1)
    if Enum.all?(corners), do: List.to_tuple(corners)
  end

  defp gamut(_color), do: nil

  defp point(%{"x" => x, "y" => y}) when is_number(x) and is_number(y), do: {x, y}
  defp point(_point), do: nil

  defp round4(value), do: Float.round(value * 1.0, 4)
end
