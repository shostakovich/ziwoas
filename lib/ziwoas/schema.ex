defmodule Ziwoas.Schema do
  @moduledoc """
  Base for Ecto schemas over the Rails-owned SQLite tables. Rails owns `db/schema.rb`
  until cutover, so there are no Ecto migrations: every schema mirrors a table exactly
  (`test/ziwoas/rails_contract_test.exs` checks this against `db/schema.rb`).

  `created_at`/`updated_at` use Rails' names and on-disk format.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [
        type: Ziwoas.Ecto.RailsDateTime,
        inserted_at: :created_at,
        autogenerate: {Ziwoas.Ecto.RailsDateTime, :utc_now, []}
      ]
    end
  end
end
