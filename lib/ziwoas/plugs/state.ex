defmodule Ziwoas.Plugs.State do
  @moduledoc "Last known relay output of a plug (`plug_states`)."
  use Ziwoas.Schema

  alias Ziwoas.Repo

  schema "plug_states" do
    field :output, :boolean
    field :plug_id, :string
    timestamps()
  end

  # ActiveModel::Type::Boolean::FALSE_VALUES as JSON can carry them (Ruby's 0 == 0.0).
  @false_values [false, 0, +0.0, -0.0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  @doc """
  ActiveRecord's cast of a value into the boolean `output` column: nil and `""`
  are nil, the false words false, anything else true.
  """
  @spec cast_output(term) :: boolean | nil
  def cast_output(value) when value in [nil, ""], do: nil
  def cast_output(value), do: value not in @false_values

  @doc """
  Rails' `Plugs::State.record_output`: stores the cast output for the plug and
  returns true when it changed. `{:error, :invalid}` for a value that casts to nil
  (the model's inclusion validation).
  """
  @spec record_output(String.t(), term) :: boolean | {:error, :invalid}
  def record_output(plug_id, raw) do
    case cast_output(raw) do
      nil ->
        {:error, :invalid}

      output ->
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
end
