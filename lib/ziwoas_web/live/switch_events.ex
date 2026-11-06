defmodule ZiwoasWeb.SwitchEvents do
  @moduledoc """
  The presses Schalten and a device's page share: switching a plug or heater and stepping a
  Heiztemperatur. Each runs as a `start_async` named after the device, at most one per name;
  `settle/2` reads its result.
  """
  import Phoenix.Component, only: [update: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias Ziwoas.{Heating, Switching}

  @plug_failed "Schalten fehlgeschlagen — Steckdose nicht erreichbar"
  @plug_rejected "Schalten fehlgeschlagen — Steckdose lehnt ab"
  @heater_failed "Schalten fehlgeschlagen — Heizung nicht erreichbar"
  @heat_c_failed "Heiztemperatur nicht geändert — Heizung nicht erreichbar"

  @spec switch_plug(Phoenix.LiveView.Socket.t(), Ziwoas.Plugs.Plug.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def switch_plug(socket, plug, state) when state in ~w[on off] do
    action = if state == "on", do: :on, else: :off
    start(socket, {:switch, plug.id}, fn -> Switching.switch(plug, action, :manual) end)
  end

  @spec switch_heater(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def switch_heater(socket, key, state) when state in ~w[heat frost] do
    heater_state = if state == "heat", do: :heat, else: :frost
    start(socket, {:switch_heater, key}, fn -> Heating.switch(key, heater_state) end)
  end

  @spec step_heat_c(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def step_heat_c(socket, key, step) when step in ~w[up down] do
    direction = if step == "up", do: :up, else: :down
    start(socket, {:heat_c, key}, fn -> Heating.step_heat_c(key, direction) end)
  end

  @doc "Runs `fun` as the async `name` unless one by that name is still running."
  @spec start(Phoenix.LiveView.Socket.t(), term, (-> term)) :: Phoenix.LiveView.Socket.t()
  def start(socket, name, fun) do
    if MapSet.member?(socket.assigns.pending, name),
      do: socket,
      else: socket |> update(:pending, &MapSet.put(&1, name)) |> start_async(name, fun)
  end

  @doc "Marks `name` done; `:ok` when the press went through or changed nothing, else the message."
  @spec settle(Phoenix.LiveView.Socket.t(), term, term) ::
          {Phoenix.LiveView.Socket.t(), :ok | {:error, String.t()}}
  def settle(socket, name, result),
    do: {update(socket, :pending, &MapSet.delete(&1, name)), outcome(name, result)}

  defp outcome({:switch, _plug_id}, {:ok, {:ok, _command}}), do: :ok

  defp outcome({:switch, _plug_id}, {:ok, {:error, {:rejected, _reason}}}),
    do: {:error, @plug_rejected}

  defp outcome({:switch, _plug_id}, _failed), do: {:error, @plug_failed}

  defp outcome({kind, _key}, {:ok, {:ok, _result}}) when kind in [:switch_heater, :heat_c],
    do: :ok

  defp outcome({kind, _key}, {:ok, {:error, reason}})
       when kind in [:switch_heater, :heat_c] and reason in [:limit, :not_found],
       do: :ok

  defp outcome({:switch_heater, _key}, _failed), do: {:error, @heater_failed}
  defp outcome({:heat_c, _key}, _failed), do: {:error, @heat_c_failed}
end
