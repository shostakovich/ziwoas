defmodule Ziwoas.Switching.Row do
  @moduledoc """
  One switchable plug on the Schalten page (`Ziwoas.Switching.rows/3`): its
  schedule folded into entries, its relay state, the latest command, the next
  edge within a week and its latest measurement.
  """
  alias Ziwoas.Plugs.{Plug, State}
  alias Ziwoas.Switching.{Command, Edges, Schedule}

  @enforce_keys [
    :plug,
    :entries,
    :state,
    :last_command,
    :next_edge,
    :watt,
    :last_seen_ts,
    :offline,
    :now
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          plug: Plug.t(),
          entries: [Schedule.entry()],
          state: State.t() | nil,
          last_command: Command.t() | nil,
          next_edge: Edges.Edge.t() | nil,
          watt: float | nil,
          last_seen_ts: integer | nil,
          offline: boolean,
          now: DateTime.t()
        }

  @doc "Seconds since the latest sample, nil without one."
  @spec age(t) :: float | nil
  def age(%__MODULE__{last_seen_ts: nil}), do: nil

  def age(%__MODULE__{last_seen_ts: ts, now: now}),
    do: DateTime.diff(now, DateTime.from_unix!(ts), :microsecond) / 1_000_000

  @doc "The measurement's offline rule (`Ziwoas.Plugs.latest_measurements/3`)."
  @spec offline?(t) :: boolean
  def offline?(%__MODULE__{offline: offline}), do: offline

  @doc """
  The fresher signal wins: a command newer than the last confirmed device state
  shows optimistically until the Shelly status message catches up.
  """
  @spec on?(t) :: boolean
  def on?(%__MODULE__{last_command: command, state: state}) do
    cond do
      command && fresher?(command, state) -> command.action == :on
      state -> state.output
      true -> false
    end
  end

  defp fresher?(_command, nil), do: true
  defp fresher?(_command, %State{updated_at: nil}), do: true

  defp fresher?(command, state),
    do: DateTime.compare(command.inserted_at, state.updated_at) != :lt

  @doc "Schaltzeiten, not rows: a Zeitfenster is one row and two of them."
  @spec rule_count(t) :: non_neg_integer
  def rule_count(%__MODULE__{entries: entries}),
    do: entries |> Enum.map(&length(Schedule.rules(&1))) |> Enum.sum()
end
