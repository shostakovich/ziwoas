defmodule Ziwoas.TestProcess do
  @moduledoc """
  State a test keeps in its process dictionary for the processes it starts as well:
  a LiveView under `Phoenix.LiveViewTest` or a `Task` (`$callers`), a
  `start_supervised` child (`$ancestors`). `Ziwoas.TestClock` keeps its
  instant here.
  """

  @doc "The processes that started this one, nearest first: `$callers`, then `$ancestors`."
  @spec lineage() :: [pid]
  def lineage,
    do: Enum.filter(Process.get(:"$callers", []) ++ Process.get(:"$ancestors", []), &is_pid/1)

  @spec put(term, term) :: :ok
  def put(key, value) do
    Process.put({__MODULE__, key}, value)
    :ok
  end

  @spec delete(term) :: :ok
  def delete(key) do
    Process.delete({__MODULE__, key})
    :ok
  end

  @doc "The value under `key` in this process, else in the nearest of its `lineage/0`."
  @spec get(term) :: term | nil
  def get(key) do
    key = {__MODULE__, key}

    Process.get(key) || Enum.find_value(lineage(), &dictionary_value(&1, key))
  end

  defp dictionary_value(pid, key) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        with {_key, value} <- List.keyfind(dictionary, key, 0), do: value

      nil ->
        nil
    end
  end
end

defmodule Ziwoas.TestClock do
  @moduledoc """
  `Ziwoas.Clock`'s source in tests (`config :ziwoas, clock: Ziwoas.TestClock` in
  config/test.exs): the system clock, unless a test froze it for itself and the
  processes it starts. A frozen instant stands still.
  """
  @behaviour Ziwoas.Clock

  alias Ziwoas.TestProcess

  @doc "Pins now until `unfreeze/0`; takes a `DateTime` or ISO 8601 text with an offset."
  @spec freeze(DateTime.t() | String.t()) :: :ok
  def freeze(instant), do: TestProcess.put(:now, Ziwoas.Clock.parse!(instant))

  @spec unfreeze() :: :ok
  def unfreeze, do: TestProcess.delete(:now)

  @impl true
  def utc_now, do: TestProcess.get(:now) || DateTime.utc_now()
end
