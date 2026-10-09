defmodule Ziwoas.LampPower do
  @moduledoc false
  import ExUnit.Assertions
  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Ziwoas.{FakeGoveeBridge, Repo, TestClock}
  alias Ziwoas.Lights.PowerUp
  alias Ziwoas.Switching.Command

  @doc "Starts the power-up with its task supervisor; ticks only come when a test sends them."
  def start_power_up! do
    ExUnit.Callbacks.start_supervised!({Task.Supervisor, name: Ziwoas.Lights.Tasks})
    power_up = ExUnit.Callbacks.start_supervised!({PowerUp, retry_ms: 3_600_000})
    Sandbox.allow(Repo, self(), power_up)
    power_up
  end

  @doc "Plays a LAN reply of the lamp and waits until the power-up has handled it."
  def hear(key, telemetry) do
    FakeGoveeBridge.hear(key, telemetry)
    :sys.get_state(PowerUp)
  end

  def tick(key) do
    send(PowerUp, {:tick, key})
    :sys.get_state(PowerUp)
  end

  def later(start, seconds),
    do: start |> Ziwoas.Clock.parse!() |> DateTime.add(seconds) |> TestClock.freeze()

  def plug_commands, do: Repo.all(from c in Command, select: {c.plug_id, c.action, c.source})

  def plug_switched_on(plug_id) do
    assert_receive {:shelly_rpc, ^plug_id, "Switch.Set", %{id: 0, on: true}}
    await(fn -> plug_commands() != [] end)
  end

  def await(fun, tries \\ 200) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition not met")
      true -> Process.sleep(10) && await(fun, tries - 1)
    end
  end
end
