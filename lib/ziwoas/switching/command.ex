defmodule Ziwoas.Switching.Command do
  @moduledoc "A switch command sent to a plug, from the schedule or by hand (`switch_commands`)."
  use Ziwoas.Schema

  import Ecto.Query

  alias Ziwoas.Repo

  schema "switch_commands" do
    field :action, :string
    field :plug_id, :string
    field :source, :string
    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Whether a manual command for the plug came after `time` (`Command.manual_after?`)."
  @spec manual_after?(String.t(), DateTime.t()) :: boolean
  def manual_after?(plug_id, time) do
    Repo.exists?(
      from c in __MODULE__,
        where: c.plug_id == ^plug_id and c.source == "manual" and c.inserted_at > ^time
    )
  end
end
