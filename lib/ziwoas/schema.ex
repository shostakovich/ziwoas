defmodule Ziwoas.Schema do
  @moduledoc """
  Base for the Ecto schemas: `inserted_at`/`updated_at` as `:utc_datetime_usec`,
  stamped through `Ziwoas.Clock` so tests can pin them.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec, autogenerate: {Ziwoas.Clock, :now, []}]
    end
  end
end
