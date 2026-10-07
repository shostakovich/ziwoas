defmodule Ziwoas.Energy.LiveState do
  @moduledoc false
  alias Ziwoas.Energy.Flow

  defmodule Row do
    @moduledoc false
    @enforce_keys [:id, :name, :role, :online, :apower_w, :last_seen_ts]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @enforce_keys [:plugs, :energy_flow]
  defstruct @enforce_keys

  @type t :: %__MODULE__{plugs: [Row.t()], energy_flow: Flow.t()}
end
