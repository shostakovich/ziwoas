defmodule Ziwoas.Solakon.Control do
  @moduledoc """
  The PV page's two switches (`ZiwoasWeb.SolakonLive`): the outdoor socket (EPS
  output) and pausing the Auto-Regelung.
  """
  alias Ziwoas.Config
  alias Ziwoas.Solakon.Monitor
  alias Ziwoas.Solakon.Control.State

  @doc """
  Switches the EPS output through the monitor's connection: `{:ok, enabled}` or
  `{:error, reason}`. `nil` switches off.
  """
  @spec set_eps_output(boolean | nil, GenServer.server()) :: {:ok, boolean | nil} | {:error, term}
  def set_eps_output(enabled, monitor \\ monitor()) do
    case Monitor.set_eps_output(monitor, enabled) do
      :ok -> {:ok, enabled}
      {:error, _} = error -> error
    end
  catch
    :exit, reason -> {:error, {:monitor_down, reason}}
  end

  @doc """
  Pauses (`active` false or nil) or resumes the loop: `{:ok, state}`, or
  `{:error, :not_configured | :disabled}`.
  """
  @spec set_active(Config.t(), boolean | nil) :: {:ok, State.t()} | {:error, atom}
  def set_active(%Config{solakon: nil}, _active), do: {:error, :not_configured}
  def set_active(%Config{solakon: %{control_enabled: false}}, _active), do: {:error, :disabled}

  def set_active(%Config{}, active) do
    state = State.current!()
    {:ok, if(active, do: State.resume!(state), else: State.pause!(state))}
  end

  @doc "The monitor process the switches talk through (`config :ziwoas, :solakon_monitor`)."
  def monitor, do: Application.get_env(:ziwoas, :solakon_monitor, Monitor)
end
