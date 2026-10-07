defmodule Ziwoas.Plugs.State do
  @moduledoc "Last known relay output of a plug (`plug_states`)."
  use Ziwoas.Schema

  alias Ziwoas.Repo

  schema "plug_states" do
    field :output, :boolean
    field :plug_id, :string
    timestamps()
  end

  @doc "Stores the plug's output; true when it changed."
  @spec record_output(String.t(), boolean) :: boolean
  def record_output(plug_id, output) when is_boolean(output) do
    case Repo.get_by(__MODULE__, plug_id: plug_id) do
      nil ->
        Repo.insert!(%__MODULE__{plug_id: plug_id, output: output})
        true

      %__MODULE__{output: ^output} ->
        false

      state ->
        state |> Ecto.Changeset.change(output: output) |> Repo.update!()
        true
    end
  end
end
