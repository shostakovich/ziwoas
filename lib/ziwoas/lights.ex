defmodule Ziwoas.Lights do
  @moduledoc """
  The Govee lights: the lamps and their last known state, as the Govee bridge
  reports them (`put_lamp/1`, `put_state/2`), the commands the pages send
  (`command/3`, through `Ziwoas.Govee.Bridge`) and the lamp settings form.

  `subscribe/0` (every lamp) and `subscribe/1` (one lamp's key) deliver
  `{:updated, key}` when a lamp's state changed.
  """
  import Ecto.Query

  alias Ziwoas.{Clock, Repo}
  alias Ziwoas.Lights.{Commands, Light, State}

  @topic inspect(__MODULE__)
  @key_format ~r/\A[0-9A-Za-z]+\z/

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @spec subscribe(String.t()) :: :ok | {:error, term}
  def subscribe(key), do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, topic(key))

  @doc "Tells the subscribers that the lamp `key` changed."
  @spec notify_updated(String.t()) :: :ok
  def notify_updated(key) do
    broadcast(@topic, :updated, key)
    broadcast(topic(key), :updated, key)
    :ok
  end

  defp topic(key), do: @topic <> ":" <> key

  defp broadcast(topic, event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, topic, {event, payload})

  defmodule Zone do
    @moduledoc "One zone of a zone lamp: a main light or a side light."
    @enforce_keys [:key, :role, :on]
    defstruct @enforce_keys
    @type t :: %__MODULE__{key: String.t(), role: :main | :side, on: boolean}
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

  # --- Commands ------------------------------------------------------------------

  @doc "Whether `name` is a lamp command."
  @spec command?(term) :: boolean
  defdelegate command?(name), to: Commands

  @doc """
  Runs a lamp command from a page's parameters (`Ziwoas.Lights.Commands.run/3`):
  `{:ok, result}`, `{:error, :invalid}` for parameters that do not cast,
  `{:error, :unreachable}` when the bridge did not take it.
  """
  @spec command(Light.t(), String.t(), map) ::
          {:ok, Commands.result()} | {:error, :invalid | :unreachable}
  defdelegate command(light, name, params), to: Commands, as: :run

  @doc "The lamp's limit of zones lit at once, nil for none."
  @spec max_active_zones(Light.t()) :: pos_integer | nil
  defdelegate max_active_zones(light), to: Commands

  # --- What the bridge reports -----------------------------------------------------

  @doc """
  Creates or updates the lamp the bridge knows (`key`, `name`, `sku`,
  `supports_color`, `supports_color_temp`, `color_temp_min_k`, `color_temp_max_k`,
  `zones`, `scenes`). A stored name is kept: it is the settings form's. An empty
  zone or scene list is stored as NULL.
  """
  @spec put_lamp(map) :: :ok | {:error, :invalid}
  def put_lamp(%{key: key} = lamp) do
    {light, name} =
      case Repo.get_by(Light, key: key) do
        nil -> {%Light{key: key}, present(lamp[:name]) || key}
        light -> {light, light.name}
      end

    changes =
      %{
        name: name,
        supports_color: lamp[:supports_color] == true,
        supports_color_temp: lamp[:supports_color_temp] == true,
        zones: blank_to_nil(lamp[:zones]),
        firmware_scenes: blank_to_nil(lamp[:scenes])
      }
      |> put_unless_nil(:sku, present(lamp[:sku]))
      |> put_unless_nil(:color_temp_min_k, lamp[:color_temp_min_k])
      |> put_unless_nil(:color_temp_max_k, lamp[:color_temp_max_k])

    if is_binary(key) and Regex.match?(@key_format, key) do
      light |> Ecto.Changeset.change(changes) |> Repo.insert_or_update!()
      :ok
    else
      {:error, :invalid}
    end
  end

  @doc """
  Records the state the bridge reports for the lamp `key` and tells the
  subscribers: `on` and `reachable` always, `brightness`, `color`
  (`%{r:, g:, b:}`), `color_temp_k` and `zone_states` when given; an absent
  field stays untouched, zone bits merge into the stored ones.
  """
  @spec put_state(String.t(), map) :: :ok
  def put_state(key, state) when is_binary(key) and key != "" do
    row = Repo.get_by(State, light_key: key) || %State{light_key: key}

    changes =
      %{on: state.on, reachable: state.reachable, last_seen_at: Clock.now()}
      |> put_present(state, :brightness)
      |> put_present(state, :color_temp_k)
      |> put_color(state)
      |> put_zones(row, state)

    row |> Ecto.Changeset.change(changes) |> Repo.insert_or_update!()
    notify_updated(key)
  end

  defp put_color(changes, %{color: %{r: r, g: g, b: b}}),
    do: Map.merge(changes, %{color_r: r, color_g: g, color_b: b})

  defp put_color(changes, _state), do: changes

  defp put_zones(changes, row, %{zone_states: zones}) when zones != %{},
    do: Map.put(changes, :zone_states, Map.merge(row.zone_states || %{}, zones))

  defp put_zones(changes, _row, _state), do: changes

  defp put_present(changes, state, key),
    do: if(Map.has_key?(state, key), do: Map.put(changes, key, state[key]), else: changes)

  defp put_unless_nil(changes, _key, nil), do: changes
  defp put_unless_nil(changes, key, value), do: Map.put(changes, key, value)

  defp blank_to_nil([]), do: nil
  defp blank_to_nil(list), do: list

  defp present(nil), do: nil
  defp present(text), do: if(String.trim(text) == "", do: nil, else: text)

  # --- Lamp readings ------------------------------------------------------------------

  @doc "The white range the Govee capabilities reported, else 2700–6500 K."
  @spec color_temp_range(Light.t()) :: {pos_integer, pos_integer}
  def color_temp_range(light), do: {Light.color_temp_min_k(light), Light.color_temp_max_k(light)}

  @doc "The lamp's Govee scenes, always a list."
  @spec scenes(Light.t()) :: [String.t()]
  def scenes(light), do: Light.firmware_scenes(light)

  # --- Snapshot readings -------------------------------------------------------

  def on?(%Snapshot{state: state}), do: state != nil and state.on == true
  def brightness(%Snapshot{state: state}), do: (state && state.brightness) || 0
  def color_temp_k(%Snapshot{state: state}), do: state && state.color_temp_k

  def rgb(%Snapshot{state: %State{color_r: r, color_g: g, color_b: b}}) when not is_nil(r),
    do: {r, g, b}

  def rgb(%Snapshot{}), do: nil

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
      case Light.zone_role(key) do
        nil -> []
        role -> [%Zone{key: key, role: role, on: truthy?(bits[key])}]
      end
    end)
    |> Enum.sort_by(&if(&1.role == :main, do: 0, else: 1))
  end

  defp truthy?(value), do: value not in [nil, false]
end
