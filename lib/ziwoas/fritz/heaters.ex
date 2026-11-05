defmodule Ziwoas.Fritz.Heaters do
  @moduledoc """
  The heaters' connection to the Fritz!Box: polls every thermostat each minute, keeps the
  readings, notices a thermostat turned by hand and writes only when the state changes. The
  app's commands run here too, so the heaters' own requests reach the box one at a time.
  """
  use GenServer

  require Logger

  alias Ziwoas.{Clock, Heating}
  alias Ziwoas.Fritz.{DectClient, Thermostat}
  alias Ziwoas.Heating.Heater

  @poll_ms 60_000
  @first_poll_ms 5_000
  @call_timeout_ms 30_000
  @table __MODULE__

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The latest poll's thermostats by key; nil while the box does not answer or nothing polls."
  @spec readings() :: Heating.readings() | nil
  def readings do
    case :ets.lookup(@table, :readings) do
      [{:readings, readings}] -> readings
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec switch(String.t(), Heating.Decision.state()) ::
          {:ok, Heating.Decision.t()} | {:error, term}
  def switch(key, state), do: call({:switch, key, state})

  @spec step_heat_c(String.t(), :up | :down) :: {:ok, Heater.t()} | {:error, term}
  def step_heat_c(key, direction), do: call({:step_heat_c, key, direction})

  @doc "Decides again without polling, e.g. after a window changed."
  @spec decide() :: :ok
  def decide, do: GenServer.cast(__MODULE__, :decide)

  defp call(request) do
    deadline = System.monotonic_time(:millisecond) + @call_timeout_ms
    GenServer.call(__MODULE__, {request, deadline}, @call_timeout_ms)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])

    state = %{
      client: Keyword.fetch!(opts, :client),
      zone: Keyword.fetch!(opts, :zone),
      timer: Keyword.get(opts, :timer, &Process.send_after/3),
      readings: nil
    }

    # Not at once: a poll that crashes the process must not loop at network speed.
    state.timer.(self(), :poll, @first_poll_ms)
    {:ok, publish(state)}
  end

  @impl true
  def handle_info(:poll, state) do
    state = state |> poll() |> decide_all() |> publish()
    state.timer.(self(), :poll, @poll_ms)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:decide, state), do: {:noreply, state |> decide_all() |> publish()}

  # A command its caller gave up on changes nothing; the client guards each request itself.
  @impl true
  def handle_call({request, deadline}, _from, state) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:reply, {:error, :deadline_exceeded}, state}
    else
      {reply, state} = command(request, deadline, state)
      {:reply, reply, state}
    end
  end

  defp command({:switch, key, heater_state}, deadline, state) do
    now = Clock.now()

    with {:ok, heater} <- present(state, key),
         {:ok, state} <- write(state, heater, Heating.target(heater, heater_state), deadline) do
      heater = Heating.put_press!(Heating.get_heater(key), heater_state, now)
      {{:ok, Heating.decide(heater, now, state.zone)}, publish(state)}
    else
      {:error, reason} -> {{:error, reason}, state}
      {:error, reason, state} -> {{:error, reason}, state}
    end
  end

  defp command({:step_heat_c, key, direction}, deadline, state) do
    with {:ok, heater} <- present(state, key),
         {:ok, celsius} <- Heater.step(heater.heat_c, direction),
         {:ok, state} <- write_if_heating(state, heater, celsius, deadline) do
      {{:ok, Heating.put_heat_c!(Heating.get_heater(key), celsius)}, publish(state)}
    else
      {:error, reason} -> {{:error, reason}, state}
      {:error, reason, state} -> {{:error, reason}, state}
    end
  end

  defp present(state, key) do
    case {Heating.get_heater(key), state.readings && state.readings[key]} do
      {nil, _thermostat} -> {:error, :not_found}
      {heater, %Thermostat{present: true}} -> {:ok, heater}
      {_heater, _absent} -> {:error, :offline}
    end
  end

  defp write_if_heating(state, heater, celsius, deadline) do
    if Heating.decide(heater, Clock.now(), state.zone).state == :heat,
      do: write(state, heater, {:heat, celsius}, deadline),
      else: {:ok, state}
  end

  defp poll(state) do
    case DectClient.thermostats(state.client) do
      {:ok, thermostats, client} ->
        now = Clock.now()

        for thermostat <- thermostats,
            do: thermostat |> Heating.register() |> notice(thermostat, now)

        %{state | client: client, readings: Map.new(thermostats, &{&1.key, &1})}

      {:error, reason, client} ->
        Logger.warning("FritzHeaters: #{inspect(reason)}")
        %{state | client: client, readings: nil}
    end
  end

  # A target ZiWoAS did not set means someone turned the thermostat: a press, from this poll.
  defp notice(heater, %Thermostat{present: true, busy: false, target: target}, now)
       when not is_nil(target) do
    case Heater.written(heater) do
      ^target ->
        heater

      nil when target == :off ->
        Heating.put_written!(heater, target)

      _other ->
        heater |> Heating.put_press!(Heater.state_of(target), now) |> Heating.put_written!(target)
    end
  end

  defp notice(heater, _thermostat, _now), do: heater

  defp decide_all(state) do
    now = Clock.now()
    Enum.reduce(Heating.heaters(), state, &decide_one(&1, &2, now))
  end

  # Only a change of state is written, so a temperature set on the thermostat stays until then.
  defp decide_one(heater, state, now) do
    decision = Heating.decide(heater, now, state.zone)

    with {:ok, heater} <- present(state, heater.key),
         false <- decision.state == Heater.written_state(heater) do
      case write(state, heater, Heating.target(heater, decision.state), :infinity) do
        {:ok, state} ->
          state

        {:error, reason, state} ->
          Logger.warning("FritzHeaters #{heater.key}: #{inspect(reason)}")
          state
      end
    else
      _absent_or_unchanged -> state
    end
  end

  defp write(state, heater, target, deadline) do
    case DectClient.set_target(state.client, heater.ain, target, deadline: deadline) do
      {:ok, client} ->
        Heating.put_written!(heater, target)

        {:ok,
         %{state | client: client, readings: with_target(state.readings, heater.key, target)}}

      {:error, reason, client} ->
        {:error, reason, %{state | client: client}}
    end
  end

  defp with_target(readings, key, target) do
    case readings do
      %{^key => thermostat} -> %{readings | key => %{thermostat | target: target}}
      _ -> readings
    end
  end

  defp publish(state) do
    :ets.insert(@table, {:readings, state.readings})
    Heating.notify(state.readings)
    state
  end
end
