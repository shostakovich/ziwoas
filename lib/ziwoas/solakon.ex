defmodule Ziwoas.Solakon do
  @moduledoc false
  import Ecto.Query

  alias Ziwoas.{Config, Repo}
  alias Ziwoas.Solakon.{Alarms, Control, History, Monitor, PvHour, Reading, Snapshot}

  @topic inspect(__MODULE__)

  @spec subscribe() :: :ok | {:error, term}
  def subscribe, do: Phoenix.PubSub.subscribe(Ziwoas.PubSub, @topic)

  @spec notify_reading(Reading.t()) :: :ok
  def notify_reading(%Reading{} = reading) do
    broadcast(:reading, reading)
    :ok
  end

  @spec notify_snapshot(Snapshot.t()) :: :ok
  def notify_snapshot(%Snapshot{} = snapshot) do
    broadcast(:snapshot, snapshot)
    :ok
  end

  defp broadcast(event, payload),
    do: Phoenix.PubSub.broadcast(Ziwoas.PubSub, @topic, {event, payload})

  @spec insert_reading(map, DateTime.t()) :: {:ok, Reading.t()} | {:error, Ecto.Changeset.t()}
  def insert_reading(state, taken_at), do: state |> Reading.from_state(taken_at) |> Repo.insert()

  @spec latest_reading() :: Reading.t() | nil
  def latest_reading, do: Repo.one(from r in Reading, order_by: [desc: r.taken_at], limit: 1)

  @spec fresh_reading(DateTime.t(), integer) :: Reading.t() | nil
  def fresh_reading(now, stale_after_s \\ Reading.stale_after_s()) do
    since = DateTime.add(now, -stale_after_s)

    Repo.one(
      from r in Reading,
        where: r.taken_at >= ^since,
        order_by: [desc: r.taken_at],
        limit: 1
    )
  end

  @spec insert_snapshot(map, DateTime.t()) :: {:ok, Snapshot.t()} | {:error, Ecto.Changeset.t()}
  def insert_snapshot(data, taken_at), do: data |> Snapshot.from_data(taken_at) |> Repo.insert()

  @spec latest_snapshot() :: Snapshot.t() | nil
  def latest_snapshot, do: Repo.one(from s in Snapshot, order_by: [desc: s.taken_at], limit: 1)

  @spec conditions(Reading.t() | Snapshot.t()) :: [Alarms.condition()]
  def conditions(%Snapshot{} = snapshot),
    do: Alarms.conditions(snapshot, snapshot.bms_faults || [])

  def conditions(%Reading{} = reading), do: Alarms.conditions(reading)

  @doc "A missing row reads as active."
  @spec control_active?() :: boolean
  def control_active?, do: Control.State.active?(Control.state())

  @spec set_control_active(Config.t(), boolean | nil) ::
          {:ok, boolean} | {:error, :not_configured | :disabled}
  def set_control_active(%Config{solakon: nil}, _active), do: {:error, :not_configured}

  def set_control_active(%Config{solakon: %{control_enabled: false}}, _active),
    do: {:error, :disabled}

  def set_control_active(%Config{}, active) do
    state = Control.state!()
    state = if active, do: Control.resume!(state), else: Control.pause!(state)
    {:ok, Control.State.active?(state)}
  end

  @spec set_eps_output(boolean | nil, GenServer.server()) :: {:ok, boolean | nil} | {:error, term}
  def set_eps_output(enabled, monitor \\ Monitor) do
    case Monitor.set_eps_output(monitor, enabled) do
      :ok -> {:ok, enabled}
      {:error, _} = error -> error
    end
  catch
    :exit, reason -> {:error, {:monitor_down, reason}}
  end

  @spec history(term, DateTime.t(), String.t()) :: History.t()
  def history(range, now, zone), do: History.build(range, now, zone)

  @spec pv_hours() :: [PvHour.t()]
  def pv_hours, do: Repo.all(from h in PvHour, order_by: h.started_at)

  @spec pv_hours_between(DateTime.t(), DateTime.t()) :: [PvHour.t()]
  def pv_hours_between(from, to) do
    Repo.all(
      from h in PvHour,
        where: h.started_at >= ^from and h.started_at < ^to,
        order_by: h.started_at
    )
  end

  @spec latest_pv_hour_start() :: DateTime.t() | nil
  def latest_pv_hour_start, do: Repo.one(from h in PvHour, select: max(h.started_at))
end
