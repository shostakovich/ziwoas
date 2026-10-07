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
end
