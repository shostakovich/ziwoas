defmodule Ziwoas.Heating.Window do
  @moduledoc "A weekly heating window; `days` are the ISO weekdays it starts on."
  use Ziwoas.Schema

  alias Ziwoas.Switching.{Rule, Schedule}

  @type t :: %__MODULE__{}

  schema "heater_windows" do
    field :heater_key, :string
    field :on_minute, :integer
    field :off_minute, :integer
    field :days, {:array, :integer}, default: []
    field :enabled, :boolean, default: true
    timestamps()
  end

  @doc "As the plugs' schedule entry, so the plugs' list renders it."
  @spec entry(t) :: Schedule.Window.t()
  def entry(%__MODULE__{} = window) do
    half =
      &%Rule{
        id: window.id,
        group_id: to_string(window.id),
        action: &1,
        at_minute: &2,
        days: window.days,
        enabled: window.enabled
      }

    %Schedule.Window{on: half.(:on, window.on_minute), off: half.(:off, window.off_minute)}
  end
end
