defmodule Ziwoas.Lights do
  @moduledoc """
  The Govee lights as the Schalten page and a lamp's page show them, and the
  lamp settings form.

  `subscribe/0` (every lamp) and `subscribe/1` (one lamp's key) deliver
  `{:updated, key}` when a lamp's state changed.
  """
  import Ecto.Query

  alias Ziwoas.Lights.{Light, State}
  alias Ziwoas.{Live, Repo}

  @topic inspect(__MODULE__)

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @spec subscribe(String.t()) :: :ok | {:error, term}
  def subscribe(key), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, topic(key))

  @doc "Tells the subscribers that the lamp `key` changed."
  @spec notify_updated(String.t()) :: :ok
  def notify_updated(key) do
    broadcast(@topic, :updated, key)
    broadcast(topic(key), :updated, key)
    Live.broadcast("light_#{key}", {:light_updated, key})
    Live.broadcast("lights", {:light_updated, key})
    :ok
  end

  defp topic(key), do: @topic <> ":" <> key

  defp broadcast(topic, event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, topic, {event, payload})

  defmodule Zone do
    @moduledoc "One zone of a zone lamp."
    @enforce_keys [:key, :label, :role, :on]
    defstruct @enforce_keys
    @type t :: %__MODULE__{key: String.t(), label: String.t(), role: String.t(), on: boolean}
  end

  defmodule Snapshot do
    @moduledoc "A light and its last known state."
    @enforce_keys [:light, :state]
    defstruct @enforce_keys
    @type t :: %__MODULE__{light: Light.t(), state: State.t() | nil}
  end

  @spec get_by_key(String.t()) :: Light.t() | nil
  def get_by_key(key), do: Repo.get_by(Light, key: key)

  @doc "The light with `key`; raises `Ecto.NoResultsError` (a 404) when there is none."
  @spec get_by_key!(String.t()) :: Light.t()
  def get_by_key!(key), do: Repo.get_by!(Light, key: key)

  @doc "Every light by name with its state."
  @spec snapshots() :: [Snapshot.t()]
  def snapshots do
    lights = Repo.all(from l in Light, order_by: l.name)
    keys = Enum.map(lights, & &1.key)
    states = Map.new(Repo.all(from s in State, where: s.light_key in ^keys), &{&1.light_key, &1})
    Enum.map(lights, &%Snapshot{light: &1, state: states[&1.key]})
  end

  @spec snapshot(Light.t()) :: Snapshot.t()
  def snapshot(light),
    do: %Snapshot{light: light, state: Repo.get_by(State, light_key: light.key)}

  @doc "The settings form's changeset: name and Shelly plug."
  @spec change_settings(Light.t(), map) :: Ecto.Changeset.t()
  def change_settings(light, params \\ %{}), do: Light.settings_changeset(light, params)

  @doc "Saves name and Shelly plug, or answers the changeset with its errors."
  @spec update_settings(Light.t(), map) :: {:ok, Light.t()} | {:error, Ecto.Changeset.t()}
  def update_settings(light, params), do: light |> change_settings(params) |> Repo.update()

  # --- Snapshot readings -------------------------------------------------------

  def on?(%Snapshot{state: state}), do: state != nil and state.on == true
  def brightness(%Snapshot{state: state}), do: (state && state.brightness) || 0
  def color_temp_k(%Snapshot{state: state}), do: state && state.color_temp_k

  def rgb(%Snapshot{state: %State{color_r: r, color_g: g, color_b: b}}) when not is_nil(r),
    do: {r, g, b}

  def rgb(%Snapshot{}), do: nil

  @doc "`#rrggbb`, nil without a colour."
  def color_hex(snapshot) do
    case rgb(snapshot) do
      nil -> nil
      {r, g, b} -> "#" <> Enum.map_join([r, g, b], &hex_byte/1)
    end
  end

  defp hex_byte(value),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(2, "0")

  @doc "White when there is no colour, or a positive colour temperature is set."
  def white?(snapshot), do: (color_temp_k(snapshot) || 0) > 0 or is_nil(rgb(snapshot))

  def zone_lamp?(%Snapshot{light: light}), do: Light.zone_lamp?(light)

  @doc "The lamp's zones with their on/off bits, main zones first."
  @spec zones(Snapshot.t()) :: [Zone.t()]
  def zones(%Snapshot{light: light, state: state}) do
    bits = (state && state.zone_states) || %{}

    light
    |> Light.zones()
    |> Enum.flat_map(fn key ->
      case Light.zone_meta(key) do
        {label, role} -> [%Zone{key: key, label: label, role: role, on: truthy?(bits[key])}]
        nil -> []
      end
    end)
    |> Enum.sort_by(&if(&1.role == "main", do: 0, else: 1))
  end

  defp truthy?(value), do: value not in [nil, false]
end
