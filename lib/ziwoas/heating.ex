defmodule Ziwoas.Heating do
  @moduledoc """
  The heaters: FRITZ!DECT 301 thermostats with a Heiztemperatur, weekly windows and manual
  presses, and the decision what each should do now. `Ziwoas.Fritz.Heaters` holds the live
  readings and is the only one that talks to the box.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Ziwoas.Fritz.{Heaters, Thermostat}
  alias Ziwoas.Heating.{Decision, Heater, Row, Window}
  alias Ziwoas.{Repo, Rooms}
  alias Ziwoas.Switching.Rule
  alias Ziwoas.Switching.Window, as: WindowForm

  @topic inspect(__MODULE__)

  @type readings :: %{String.t() => Thermostat.t()}

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @doc "Tells subscribers `{:heaters, readings}`, the latest poll's, after a poll or a command."
  @spec notify(readings | nil) :: :ok
  def notify(readings), do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {:heaters, readings})

  @spec heaters() :: [Heater.t()]
  def heaters, do: Repo.all(from h in Heater, order_by: [h.name, h.key])

  @spec get_heater(String.t()) :: Heater.t() | nil
  def get_heater(key), do: Repo.get_by(Heater, key: key)

  @doc "Adds a thermostat the box reports for the first time; a known one takes the box's name."
  @spec register(Thermostat.t()) :: Heater.t()
  def register(%Thermostat{key: key, ain: ain, name: name}) do
    (get_heater(key) || %Heater{key: key})
    |> Changeset.change(ain: ain, name: name)
    |> Repo.insert_or_update!()
  end

  @spec change_room(Heater.t(), map) :: Changeset.t()
  def change_room(heater, params \\ %{}),
    do: heater |> Heater.room_changeset(params) |> Rooms.validate_room()

  @doc "Puts the heater into a room; a blank room takes it out of any."
  @spec put_room(Heater.t(), map) :: {:ok, Heater.t()} | {:error, Changeset.t()}
  def put_room(heater, params), do: heater |> change_room(params) |> Repo.update()

  @spec put_written!(Heater.t(), Thermostat.target()) :: Heater.t()
  def put_written!(heater, target),
    do: heater |> Heater.written_changeset(target) |> Repo.update!()

  @spec put_heat_c!(Heater.t(), float) :: Heater.t()
  def put_heat_c!(heater, celsius),
    do: heater |> Changeset.change(heat_c: celsius * 1.0) |> Repo.update!()

  @doc "The latest poll's thermostats; nil while the box does not answer."
  @spec readings() :: readings | nil
  defdelegate readings, to: Heaters

  @doc "A press in the app; it is recorded only once the thermostat took it."
  @spec switch(String.t(), Decision.state()) :: {:ok, Decision.t()} | {:error, term}
  def switch(key, state) when state in [:heat, :frost], do: Heaters.switch(key, state)

  @doc "Makes the Heiztemperatur half a degree warmer or colder; a heater that heats takes it at once."
  @spec step_heat_c(String.t(), :up | :down) :: {:ok, Heater.t()} | {:error, term}
  def step_heat_c(key, direction) when direction in [:up, :down],
    do: Heaters.step_heat_c(key, direction)

  @spec put_press!(Heater.t(), Decision.state(), DateTime.t()) :: Heater.t()
  def put_press!(heater, state, at),
    do: heater |> Changeset.change(pressed_state: state, pressed_at: at) |> Repo.update!()

  @spec decide(Heater.t(), DateTime.t(), String.t()) :: Decision.t()
  def decide(heater, now, zone), do: decide(heater, windows(heater.key), now, zone)

  defp decide(heater, windows, now, zone),
    do: Decision.decide(windows, Heater.press(heater), now, zone)

  @spec target(Heater.t(), Decision.state()) :: Thermostat.target()
  def target(heater, :heat), do: {:heat, heater.heat_c}
  def target(_heater, :frost), do: :off

  @doc "While the box answers, only the heaters it lists; else every known one, offline."
  @spec rows(readings | nil, DateTime.t(), String.t()) :: [Row.t()]
  def rows(readings, now, zone) do
    for heater <- heaters(), is_nil(readings) or Map.has_key?(readings, heater.key) do
      windows = windows(heater.key)

      %Row{
        heater: heater,
        entries: Enum.map(windows, &Window.entry/1),
        decision: decide(heater, windows, now, zone),
        thermostat: readings && readings[heater.key],
        now: now
      }
    end
  end

  @spec windows(String.t()) :: [Window.t()]
  def windows(key),
    do: Repo.all(from w in Window, where: w.heater_key == ^key, order_by: [w.on_minute, w.id])

  @spec window(String.t(), term) :: Window.t() | nil
  def window(key, id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> Repo.one(from w in Window, where: w.heater_key == ^key and w.id == ^id)
      _ -> nil
    end
  end

  def window(_key, _id), do: nil

  @doc "The plugs' window form, so both share fields, validation and messages."
  @spec change_window(Window.t() | nil, map) :: Changeset.t()
  def change_window(window \\ nil, attrs \\ %{}),
    do: WindowForm.changeset(form(window), attrs)

  defp form(nil), do: %WindowForm{}

  defp form(%Window{} = window),
    do: WindowForm.new(to_string(window.id), window.on_minute, window.off_minute, window.days)

  @spec save_window(String.t(), map, Window.t() | nil) ::
          {:ok, Window.t()} | {:error, Changeset.t()}
  def save_window(key, attrs, window \\ nil) do
    with {:ok, form} <- window |> change_window(attrs) |> Changeset.apply_action(:insert) do
      (window || %Window{heater_key: key})
      |> Changeset.change(
        on_minute: Rule.minutes_from(form.on_at_time),
        off_minute: Rule.minutes_from(form.off_at_time),
        days: form.days
      )
      |> Repo.insert_or_update!()
      |> decided()
      |> then(&{:ok, &1})
    end
  end

  @spec set_window_enabled(Window.t(), boolean) :: Window.t()
  def set_window_enabled(window, enabled) when is_boolean(enabled),
    do: window |> Changeset.change(enabled: enabled) |> Repo.update!() |> decided()

  @spec delete_window(Window.t()) :: :ok
  def delete_window(window) do
    window |> Repo.delete!() |> decided()
    :ok
  end

  defp decided(window) do
    Heaters.decide()
    window
  end
end
