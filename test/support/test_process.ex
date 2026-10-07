defmodule Ziwoas.TestProcess do
  @moduledoc """
  State a test keeps in its process dictionary for the processes it starts as well:
  a LiveView under `Phoenix.LiveViewTest` or a `Task` (`$callers`), a
  `start_supervised` child (`$ancestors`). `Ziwoas.TestClock` and `Ziwoas.TestMqtt`
  keep theirs here.
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
  Freezes `Ziwoas.Clock` for a test and the processes it starts
  (`config :ziwoas, frozen_clock: {Ziwoas.TestClock, :frozen}` in config/test.exs).
  A frozen instant stands still.
  """
  alias Ziwoas.TestProcess

  @doc "Pins now until `unfreeze/0`; takes a `DateTime` or ISO 8601 text with an offset."
  @spec freeze(DateTime.t() | String.t()) :: :ok
  def freeze(instant), do: TestProcess.put(:now, Ziwoas.Clock.parse!(instant))

  @spec unfreeze() :: :ok
  def unfreeze, do: TestProcess.delete(:now)

  @doc false
  def frozen, do: TestProcess.get(:now)
end

defmodule Ziwoas.TestMqtt do
  @moduledoc """
  Records `Ziwoas.Mqtt.publish/5` instead of reaching a broker, for a test and the
  processes it starts (`config :ziwoas, mqtt_recorder: {Ziwoas.TestMqtt, :recorder}`
  in config/test.exs).
  """
  alias Ziwoas.TestProcess

  @doc """
  `publish/5` hands `(client_id, topic, payload)` — or, to a 4-arity `fun`,
  `(client_id, topic, payload, retain)` — to `fun` after the ownership check, and
  returns what `fun` returns (`:ok` or `{:error, reason}`).
  """
  @spec record(
          (String.t(), String.t(), binary -> :ok | {:error, term})
          | (String.t(), String.t(), binary, boolean -> :ok | {:error, term})
        ) :: :ok
  def record(fun) when is_function(fun, 3) or is_function(fun, 4),
    do: TestProcess.put(:mqtt_recorder, fun)

  @doc false
  def recorder, do: TestProcess.get(:mqtt_recorder)
end
