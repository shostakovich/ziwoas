defmodule Ziwoas.Heating.Heater do
  @moduledoc "A radiator thermostat the Fritz!Box knows: its Heiztemperatur, the target last set and the latest press."
  use Ziwoas.Schema

  import Ecto.Changeset

  alias Ziwoas.Fritz.Thermostat

  @type t :: %__MODULE__{}

  @min_heat_c 19.0
  @max_heat_c 22.0
  @heat_step_c 0.5
  @default_heat_c 21.0

  schema "heaters" do
    field :key, :string
    field :ain, :string
    field :name, :string
    field :heat_c, :float, default: @default_heat_c
    field :written_mode, Ecto.Enum, values: [:heat, :off, :on]
    field :written_c, :float
    field :pressed_state, Ecto.Enum, values: [:heat, :frost]
    field :pressed_at, :utc_datetime_usec
    belongs_to :room, Ziwoas.Rooms.Room
    timestamps()
  end

  @doc "The Heiztemperatur half a degree warmer or colder, within 19–22 °C."
  @spec step(float, :up | :down) :: {:ok, float} | {:error, :limit}
  def step(celsius, :up) when celsius + @heat_step_c <= @max_heat_c,
    do: {:ok, celsius + @heat_step_c}

  def step(celsius, :down) when celsius - @heat_step_c >= @min_heat_c,
    do: {:ok, celsius - @heat_step_c}

  def step(_celsius, _direction), do: {:error, :limit}

  @doc "The latest press, in the app or on the thermostat."
  @spec press(t) :: {:heat | :frost, DateTime.t()} | nil
  def press(%__MODULE__{pressed_state: nil}), do: nil
  def press(%__MODULE__{pressed_state: state, pressed_at: at}), do: {state, at}

  @spec written(t) :: Thermostat.target() | nil
  def written(%__MODULE__{written_mode: :heat, written_c: celsius}), do: {:heat, celsius}
  def written(%__MODULE__{written_mode: mode}), do: mode

  @spec written_state(t) :: :heat | :frost | nil
  def written_state(heater) do
    case written(heater) do
      nil -> nil
      target -> state_of(target)
    end
  end

  @spec state_of(Thermostat.target()) :: :heat | :frost
  def state_of(:off), do: :frost
  def state_of(_heating), do: :heat

  @doc "The temperature it heats at: the one last set, by ZiWoAS or on the thermostat."
  @spec heating_c(t) :: float | :max
  def heating_c(%__MODULE__{written_mode: :heat, written_c: celsius}), do: celsius
  def heating_c(%__MODULE__{written_mode: :on}), do: :max
  def heating_c(%__MODULE__{heat_c: celsius}), do: celsius

  @spec room_changeset(t, map) :: Ecto.Changeset.t()
  def room_changeset(heater, params), do: cast(heater, params, [:room_id])

  @spec written_changeset(t, Thermostat.target()) :: Ecto.Changeset.t()
  def written_changeset(heater, {:heat, celsius}),
    do: change(heater, written_mode: :heat, written_c: celsius * 1.0)

  def written_changeset(heater, mode) when mode in [:off, :on],
    do: change(heater, written_mode: mode, written_c: nil)
end
