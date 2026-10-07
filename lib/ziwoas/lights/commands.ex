defmodule Ziwoas.Lights.Commands do
  @moduledoc """
  The lamp commands (`Lights::Operations`, `Lights::Params`, `Lights::Contracts`):
  coerce the request parameters, send through `Ziwoas.Lights.Commander` and record
  the optimistic state (`LightState.record_state`, `record_zone_state`) inside
  `Ziwoas.Repo.write(:lights, …)`.

  Results, as Rails' `Lights::Results`: `:power` (the hero and the tile change),
  `{:zones, keys, toast}` (those zone buttons change; `toast` is nil, `:clear` or
  `%{evicted:, added:}`) and `:no_content` (fire and forget). Failures:
  `{:error, :invalid}` for parameters the contract refuses, `{:error, :commander}`
  when the broker could not be reached.
  """
  import Ecto.Query

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Govee.Types
  alias Ziwoas.Lights.{Commander, Light, State}

  @task :lights
  @commands ~w[turn zone brightness color color_temp effect scene zone_undo]
  # Hardware limit: at most N zones lit at once.
  @max_active_zones %{"H60B0" => 2}

  @type result :: :power | {:zones, [String.t()], nil | :clear | map} | :no_content

  @doc "Whether `name` is a command (`Lights::Operations[name]`)."
  def command?(name), do: name in @commands

  @spec run(Light.t(), String.t(), map) :: {:ok, result} | {:error, :invalid | :commander}
  def run(light, "turn", params) do
    with {:ok, on} <- coerce(Types.bool(params["on"])),
         :ok <- publish(light, turn_verb(light, on)) do
      Repo.write(@task, fn -> record_state(light.key, on) end)
      {:ok, :power}
    end
  end

  def run(light, "zone", params) do
    with {:ok, zone} <- zone_of(light, params["zone"]),
         {:ok, on} <- coerce(Types.bool(params["on"])) do
      evicted = if on, do: evict_for(light, zone)

      with :ok <- switch_zone(light, evicted, false),
           :ok <- switch_zone(light, zone, on) do
        toast = if evicted, do: %{evicted: evicted, added: zone}
        {:ok, {:zones, Enum.reject([zone, evicted], &is_nil/1), toast}}
      end
    end
  end

  def run(light, "zone_undo", params) do
    with {:ok, victim} <- zone_of(light, params["victim"]),
         {:ok, added} <- zone_of(light, params["added"]),
         :ok <- switch_zone(light, victim, true),
         :ok <- switch_zone(light, added, false) do
      {:ok, {:zones, [victim, added], :clear}}
    end
  end

  def run(light, "brightness", params) do
    with {:ok, value} <- ranged(params["value"], 1, 100),
         do: fire(light, {:brightness, value})
  end

  def run(light, "color", params) do
    with {:ok, r} <- ranged(params["r"], 0, 255),
         {:ok, g} <- ranged(params["g"], 0, 255),
         {:ok, b} <- ranged(params["b"], 0, 255),
         do: fire(light, {:color, %{r: r, g: g, b: b}})
  end

  # The hardware envelope first (Floor Lamps reach 2200 K), then the lamp's own range.
  def run(light, "color_temp", params) do
    with {:ok, kelvin} <- ranged(params["temp_k"], 1500, 9000) do
      kelvin = kelvin |> max(Light.color_temp_min_k(light)) |> min(Light.color_temp_max_k(light))
      fire(light, {:color_temp, kelvin})
    end
  end

  def run(light, command, params) when command in ["effect", "scene"] do
    with {:ok, scene} <- coerce(Types.name(params["effect"] || params["scene"])),
         do: fire(light, {:scene, scene})
  end

  defp fire(light, verb) do
    with :ok <- publish(light, verb), do: {:ok, :no_content}
  end

  defp turn_verb(light, on) do
    if Light.zone_lamp?(light), do: {:zone, "powerSwitch", on}, else: {:power, on}
  end

  defp switch_zone(_light, nil, _on), do: :ok

  defp switch_zone(light, zone, on) do
    with :ok <- publish(light, {:zone, zone, on}) do
      Repo.write(@task, fn -> record_zone_state(light.key, zone, on) end)
      :ok
    end
  end

  defp publish(light, verb) do
    case Commander.publish(light.key, verb) do
      :ok -> :ok
      {:error, _message} -> {:error, :commander}
    end
  end

  # Contracts::Zone: a filled string naming one of the lamp's zones.
  defp zone_of(light, zone) do
    if is_binary(zone) and zone in Light.zones(light), do: {:ok, zone}, else: {:error, :invalid}
  end

  defp ranged(value, min, max) do
    case Types.integer(value) do
      {:ok, integer} when integer >= min and integer <= max -> {:ok, integer}
      _ -> {:error, :invalid}
    end
  end

  defp coerce({:ok, value}), do: {:ok, value}
  defp coerce(:error), do: {:error, :invalid}

  @doc "The lamp's limit of zones lit at once, nil for none (`Light#max_active_zones`)."
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

  defp side?(zone), do: match?({_label, "side"}, Light.zone_meta(zone))

  defp current_zone_states(key) do
    Repo.one(from s in State, where: s.light_key == ^key, select: s.zone_states) || %{}
  end

  # --- LightState ------------------------------------------------------------------

  @doc "`LightState.record_state(key, on:)`: the row is created when missing, written when changed."
  def record_state(key, on) do
    (Repo.get_by(State, light_key: key) || %State{light_key: key})
    |> Ecto.Changeset.change(on: on)
    |> Repo.insert_or_update!()

    :ok
  end

  @doc """
  `LightState.record_zone_state`: one zone's bit, merged into the stored object.
  SQLite's `json_set` keeps the stored key order and appends a new key, as Ruby's
  `Hash#merge` does before `JSON.generate` — the map Ecto would write sorts them.
  """
  def record_zone_state(key, zone, on) do
    row = Repo.get_by(State, light_key: key) || Repo.insert!(%State{light_key: key})

    if Map.get(row.zone_states || %{}, zone) != on do
      {:ok, now} = Ziwoas.Ecto.RailsDateTime.dump(Clock.now())

      Repo.query!(
        "UPDATE light_states SET zone_states = json_set(COALESCE(zone_states, '{}'), ?, json(?)), " <>
          "updated_at = ? WHERE id = ?",
        [~s($."#{zone}"), to_string(on), now, row.id]
      )
    end

    :ok
  end
end
