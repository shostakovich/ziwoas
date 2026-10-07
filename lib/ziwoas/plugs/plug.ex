defmodule Ziwoas.Plugs.Plug do
  @moduledoc """
  A configured plug (`plugs:` in the device config, not the database): rows
  reference it only by its string `id`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ziwoas.Config.Types

  @id_format ~r/\A[a-z0-9_]+\z/

  @primary_key false
  embedded_schema do
    field :id, Types.Text
    field :name, Types.Text
    field :role, Ecto.Enum, values: [:producer, :consumer]
    field :driver, Ecto.Enum, values: [:shelly, :fritz_dect], default: :shelly
    field :ain, Types.Text
    field :room, Types.Text
    field :switchable, Types.Flag, default: false
  end

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

  @doc false
  def changeset(plug, params) do
    plug
    |> cast(params, [:id, :name, :role, :driver, :ain, :room, :switchable],
      message: &Types.cast_message/2
    )
    |> validate_required([:id, :name, :role], message: "is required")
    |> validate_format(:id, @id_format, message: "must contain only a-z, 0-9 and _")
    |> validate_ain()
    |> validate_switchable()
  end

  defp validate_ain(changeset) do
    case get_field(changeset, :driver) do
      :fritz_dect ->
        validate_required(changeset, [:ain], message: "is required for driver: fritz_dect")

      :shelly ->
        if get_field(changeset, :ain),
          do: add_error(changeset, :ain, "must not be set for driver: shelly"),
          else: changeset

      nil ->
        changeset
    end
  end

  defp validate_switchable(changeset) do
    if get_field(changeset, :switchable) == true and get_field(changeset, :role) == :producer,
      do:
        add_error(
          changeset,
          :base,
          "plug '#{get_field(changeset, :id)}' with role: producer cannot be switchable"
        ),
      else: changeset
  end
end
