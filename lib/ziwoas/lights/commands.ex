defmodule Ziwoas.Lights.Commands do
  @moduledoc """
  The lamp commands: cast the page's parameters (a schemaless changeset per
  command), hand the verb to `Ziwoas.Govee.Bridge` and record the optimistic
  state.

  Results: `:power` (the hero and the tile change),
  `{:zones, keys, toast}` (those zone buttons change; `toast` is nil, `:clear` or
  `%{evicted:, added:}`) and `{:sent, verb}` (fire and forget). Failures:
  `{:error, :invalid}` for parameters that do not cast, `{:error, :unreachable}`
  when the bridge did not take the verb.
  """
  import Ecto.Changeset
  import Ecto.Query

  alias Ziwoas.Govee.Bridge
  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.Repo

  @types %{
    "turn" => %{on: :boolean},
    "zone" => %{zone: :string, on: :boolean},
    "zone_undo" => %{victim: :string, added: :string},
    "brightness" => %{value: :integer},
    "color" => %{r: :integer, g: :integer, b: :integer},
    "color_temp" => %{temp_k: :integer},
    "effect" => %{effect: :string},
    "scene" => %{scene: :string}
  }

  # Hardware limit: at most N zones lit at once.
  @max_active_zones %{"H60B0" => 2}

  @type result :: :power | {:zones, [String.t()], nil | :clear | map} | {:sent, Bridge.verb()}

  @doc "Whether `name` is a command."
  @spec command?(term) :: boolean
  def command?(name), do: is_map_key(@types, name)

  @spec run(Light.t(), String.t(), map) :: {:ok, result} | {:error, :invalid | :unreachable}
  def run(light, command, params) do
    with {:ok, values} <- cast_params(light, command, params),
         do: execute(light, command, values)
  end

  defp cast_params(light, command, params) when is_map_key(@types, command) do
    types = @types[command]

    {%{}, types}
    |> cast(params, Map.keys(types))
    |> validate_required(Map.keys(types))
    |> validate(command, light)
    |> apply_action(:run)
    |> case do
      {:ok, values} -> {:ok, values}
      {:error, _changeset} -> {:error, :invalid}
    end
  end

  defp cast_params(_light, _command, _params), do: {:error, :invalid}

  defp validate(changeset, "zone", light),
    do: validate_inclusion(changeset, :zone, Light.zones(light))

  defp validate(changeset, "zone_undo", light) do
    changeset
    |> validate_inclusion(:victim, Light.zones(light))
    |> validate_inclusion(:added, Light.zones(light))
  end

  defp validate(changeset, "brightness", _light), do: within(changeset, :value, 1, 100)

  defp validate(changeset, "color", _light),
    do: Enum.reduce([:r, :g, :b], changeset, &within(&2, &1, 0, 255))

  # The hardware envelope (Floor Lamps reach 2200 K); the lamp's own range clamps later.
  defp validate(changeset, "color_temp", _light), do: within(changeset, :temp_k, 1500, 9000)
  defp validate(changeset, _command, _light), do: changeset

  defp within(changeset, field, min, max),
    do:
      validate_number(changeset, field, greater_than_or_equal_to: min, less_than_or_equal_to: max)

  defp execute(light, "turn", %{on: on}) do
    with :ok <- send_verb(light, turn_verb(light, on)) do
      record_state(light.key, on)
      {:ok, :power}
    end
  end

  defp execute(light, "zone", %{zone: zone, on: on}), do: switch_zone_evicting(light, zone, on)

  defp execute(light, "zone_undo", %{victim: victim, added: added}) do
    with :ok <- switch_zone(light, victim, true),
         :ok <- switch_zone(light, added, false) do
      {:ok, {:zones, [victim, added], :clear}}
    end
  end

  defp execute(light, "brightness", %{value: value}), do: fire(light, {:brightness, value})
  defp execute(light, "color", rgb), do: fire(light, {:color, rgb})

  defp execute(light, "color_temp", %{temp_k: kelvin}) do
    kelvin = kelvin |> max(Light.color_temp_min_k(light)) |> min(Light.color_temp_max_k(light))
    fire(light, {:color_temp, kelvin})
  end

  defp execute(light, "effect", %{effect: scene}), do: fire(light, {:scene, scene})
  defp execute(light, "scene", %{scene: scene}), do: fire(light, {:scene, scene})

  defp switch_zone_evicting(light, zone, on) do
    evicted = if on, do: evict_for(light, zone)

    with :ok <- switch_zone(light, evicted, false),
         :ok <- switch_zone(light, zone, on) do
      toast = if evicted, do: %{evicted: evicted, added: zone}
      {:ok, {:zones, Enum.reject([zone, evicted], &is_nil/1), toast}}
    end
  end

  defp fire(light, verb) do
    with :ok <- send_verb(light, verb), do: {:ok, {:sent, verb}}
  end

  defp turn_verb(light, on) do
    if Light.zone_lamp?(light), do: {:zone, "powerSwitch", on}, else: {:power, on}
  end

  defp switch_zone(_light, nil, _on), do: :ok

  defp switch_zone(light, zone, on) do
    with :ok <- send_verb(light, {:zone, zone, on}) do
      record_zone_state(light.key, zone, on)
      :ok
    end
  end

  defp send_verb(light, verb) do
    case Bridge.command(light.key, verb) do
      :ok -> :ok
      {:error, _reason} -> {:error, :unreachable}
    end
  end

  @doc "The lamp's limit of zones lit at once, nil for none."
  def max_active_zones(%Light{sku: sku}), do: Map.get(@max_active_zones, String.upcase(sku || ""))

  # Which lit side zone must go dark so `zone` can come on.
  defp evict_for(light, zone) do
    max = max_active_zones(light) || 0

    if side?(zone) and max > 0 do
      bits = current_zone_states(light.key)
      on_zones = Enum.filter(Light.zones(light), &(bits[&1] not in [nil, false])) -- [zone]
      if length(on_zones) >= max, do: Enum.find(on_zones, &side?/1)
    end
  end

  defp side?(zone), do: Light.zone_role(zone) == :side

  defp current_zone_states(key) do
    Repo.one(from s in State, where: s.light_key == ^key, select: s.zone_states) || %{}
  end

  # --- Recorded state ---------------------------------------------------------------

  @doc "Records the lamp's power; the row is created when missing, written when changed."
  def record_state(key, on) do
    (Repo.get_by(State, light_key: key) || %State{light_key: key})
    |> Ecto.Changeset.change(on: on)
    |> Repo.insert_or_update!()

    :ok
  end

  @doc "Records one zone's bit, merged into the stored zones."
  def record_zone_state(key, zone, on) do
    state = Repo.get_by(State, light_key: key) || %State{light_key: key}
    zones = state.zone_states || %{}

    state
    |> Ecto.Changeset.change(zone_states: Map.put(zones, zone, on))
    |> Repo.insert_or_update!()

    :ok
  end
end
