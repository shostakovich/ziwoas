defmodule Ziwoas.TestProcess do
  @moduledoc false
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
  @moduledoc false
  @behaviour Ziwoas.Clock

  alias Ziwoas.TestProcess
  @spec freeze(DateTime.t() | String.t()) :: :ok
  def freeze(instant), do: TestProcess.put(:now, Ziwoas.Clock.parse!(instant))

  @spec unfreeze() :: :ok
  def unfreeze, do: TestProcess.delete(:now)

  @impl true
  def utc_now, do: TestProcess.get(:now) || DateTime.utc_now()
end
