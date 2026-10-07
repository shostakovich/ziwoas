defmodule Ziwoas.Switching.Row do
  @moduledoc false
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

  @spec age(t) :: float | nil
  def age(%__MODULE__{last_seen_ts: nil}), do: nil

  def age(%__MODULE__{last_seen_ts: ts, now: now}),
    do: DateTime.diff(now, DateTime.from_unix!(ts), :microsecond) / 1_000_000

  @spec offline?(t) :: boolean
  def offline?(%__MODULE__{offline: offline}), do: offline

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

  @spec rule_count(t) :: non_neg_integer
  def rule_count(%__MODULE__{entries: entries}),
    do: entries |> Enum.map(&length(Schedule.rules(&1))) |> Enum.sum()
end
