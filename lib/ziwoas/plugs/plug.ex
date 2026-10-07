defmodule Ziwoas.Plugs.Plug do
  @moduledoc """
  A configured plug (`config/ziwoas.yml`, not the database): rows reference it
  only by its string `id`. Built by `Ziwoas.Config`.
  """
  @enforce_keys [:id, :role]
  defstruct [:id, :name, :role, :ain, :room, driver: :shelly, switchable: false]

  @type role :: :producer | :consumer
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          role: role,
          ain: String.t() | nil,
          room: String.t() | nil,
          driver: :shelly | :fritz_dect,
          switchable: boolean
        }
end
