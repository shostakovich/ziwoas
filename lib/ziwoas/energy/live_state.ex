defmodule Ziwoas.Energy.LiveState do
  @moduledoc """
  The live picture of the house (`Ziwoas.Energy.live_state/3`): every
  configured plug with its latest measurement, and the energy flow built from
  the consumers' draw and the inverter's fresh reading.
  """
  alias Ziwoas.Energy.Flow

  defmodule Row do
    @moduledoc "One plug as it is now; `apower_w` is nil while it is offline."
    @enforce_keys [:id, :name, :role, :online, :apower_w, :last_seen_ts]
    defstruct @enforce_keys

    @type t :: %__MODULE__{}
  end

  @enforce_keys [:plugs, :energy_flow]
  defstruct @enforce_keys

  @type t :: %__MODULE__{plugs: [Row.t()], energy_flow: Flow.t()}
end
