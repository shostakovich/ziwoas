defmodule Ziwoas.Switching.Commander do
  @moduledoc false
  alias Ziwoas.Plugs.Plug
  alias Ziwoas.{Repo, Shelly}
  alias Ziwoas.Switching.Command

  @type error ::
          :not_switchable
          | {:no_driver, atom}
          | {:unreachable, :offline | :timeout}
          | {:rejected, {integer | nil, String.t()}}

  @spec switch(Plug.t(), Command.action(), Command.source()) ::
          {:ok, Command.t()} | {:error, error}
  def switch(plug, action, source)
      when action in [:on, :off] and source in [:manual, :schedule] do
    with :ok <- switchable(plug),
         :ok <- send_switch(plug, action) do
      {:ok, Repo.insert!(%Command{plug_id: plug.id, action: action, source: source})}
    end
  end

  defp switchable(%Plug{switchable: true}), do: :ok
  defp switchable(_plug), do: {:error, :not_switchable}

  defp send_switch(%Plug{driver: :shelly} = plug, action) do
    case Shelly.call(plug.id, "Switch.Set", %{id: 0, on: action == :on}) do
      {:ok, _result} -> :ok
      {:error, {:rpc, code, message}} -> {:error, {:rejected, {code, message}}}
      {:error, reason} -> {:error, {:unreachable, reason}}
    end
  end

  defp send_switch(plug, _action), do: {:error, {:no_driver, plug.driver}}
end
