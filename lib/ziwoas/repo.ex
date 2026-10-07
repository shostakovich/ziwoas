defmodule Ziwoas.Repo do
  @moduledoc """
  The SQLite database; Ecto's migrations own its schema (`Ziwoas.Release`).

  Transactions begin IMMEDIATE (`default_transaction_mode` in `config/config.exs`):
  a deferred transaction that reads first and then writes cannot wait for another
  connection's write lock — SQLite answers SQLITE_BUSY at once and the busy timeout
  never applies — while an immediate one waits at BEGIN.
  """
  use Ecto.Repo,
    otp_app: :ziwoas,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  `time` as a `:utc_datetime_usec` column stores it (`2026-10-06T12:00:00.000000Z`), for
  raw SQL. The text compares like the instant only at that one width: an untyped
  `DateTime` parameter is written without the `Z` or the padded microseconds.
  """
  @spec dump_time(DateTime.t()) :: String.t()
  def dump_time(%DateTime{} = time) do
    {:ok, utc} = Ecto.Type.cast(:utc_datetime_usec, time)
    {:ok, text} = Ecto.Type.adapter_dump(__adapter__(), :utc_datetime_usec, utc)
    text
  end

  @doc """
  Runs `fun` and returns its result. A leftover of the time Rails and Phoenix shared
  the database, when `task` chose the database to write; it goes once no caller
  names a task any more.
  """
  @spec write(Ziwoas.Ownership.task(), (-> result)) :: result when result: var
  def write(_task, fun) when is_function(fun, 0), do: fun.()
end
