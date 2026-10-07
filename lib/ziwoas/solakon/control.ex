defmodule Ziwoas.Solakon.Control do
  @moduledoc """
  The PV page's two switches (Rails' `SolakonControlsController`), shared by
  `PATCH /solakon/eps`, `PATCH /solakon/control` and `ZiwoasWeb.SolakonLive`'s
  events: the outdoor socket (EPS output) and pausing the Auto-Regelung. Both belong
  to task `solakon_control`; callers check ownership first (`ZiwoasWeb.Owned`, the
  LiveView), and the register write refuses on its own besides.
  """
  alias Ziwoas.{Config, Repo}
  alias Ziwoas.Solakon.Monitor
  alias Ziwoas.Solakon.Control.State

  @task :solakon_control

  @doc """
  Switches the EPS output through the monitor's connection: `{:ok, enabled}` or
  `{:error, reason}`. `nil` switches off, as Rails' cast leaves it.
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
  `{:error, :not_configured | :disabled}` as Rails answers 503 and 403.
  """
  @spec set_active(Config.t(), boolean | nil) :: {:ok, State.t()} | {:error, atom}
  def set_active(%Config{solakon: nil}, _active), do: {:error, :not_configured}
  def set_active(%Config{solakon: %{control_enabled: false}}, _active), do: {:error, :disabled}

  def set_active(%Config{}, active) do
    Repo.write(@task, fn ->
      state = State.current!()
      {:ok, if(active, do: State.resume!(state), else: State.pause!(state))}
    end)
  end

  @doc "The monitor process the switches talk through (`config :ziwoas, :solakon_monitor`)."
  def monitor, do: Application.get_env(:ziwoas, :solakon_monitor, Monitor)
end
