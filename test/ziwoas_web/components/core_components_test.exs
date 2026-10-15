defmodule ZiwoasWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Setzkasten.Components.Forms
  alias ZiwoasWeb.CoreComponents

  defmodule Item do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :label, :string
      field :amount, :integer
      field :enabled, :boolean
    end

    def changeset(params) do
      %__MODULE__{}
      |> cast(params, [:label, :amount, :enabled])
      |> validate_required([:label])
      |> validate_number(:amount, greater_than_or_equal_to: 0)
      |> validate_length(:label, max: 3)
      |> Map.put(:action, :validate)
    end
  end

  defp item_form(params), do: params |> Item.changeset() |> to_form()

  describe "translate_error/1" do
    test "translates Ecto's standard messages" do
      assert CoreComponents.translate_error({"can't be blank", [validation: :required]}) ==
               "muss ausgefüllt werden"

      assert CoreComponents.translate_error(
               {"must be greater than or equal to %{number}",
                [validation: :number, kind: :greater_than_or_equal_to, number: 0]}
             ) == "muss mindestens 0 sein"

      assert CoreComponents.translate_error(
               {"should be at most %{count} character(s)",
                [count: 3, validation: :length, kind: :max, type: :string]}
             ) == "darf höchstens 3 Zeichen lang sein"

      assert CoreComponents.translate_error({"is invalid", [type: :integer, validation: :cast]}) ==
               "ist ungültig"
    end

    test "translates a unique constraint, which carries no validation" do
      assert CoreComponents.translate_error(
               {"has already been taken", [constraint: :unique, constraint_name: "x_index"]}
             ) == "ist bereits vergeben"
    end

    test "keeps German messages given at the validation and fills in their bindings" do
      assert CoreComponents.translate_error(
               {"muss zwischen %{from} und %{to} liegen", [validation: :number, from: 1, to: 9]}
             ) == "muss zwischen 1 und 9 liegen"

      assert CoreComponents.translate_error({"%{unknown} bleibt", []}) == "%{unknown} bleibt"
    end
  end

  describe "Setzkasten's input" do
    test "shows our German errors for a used field" do
      assigns = %{form: item_form(%{"label" => "", "amount" => "-1"})}

      doc =
        rendered_to_string(~H"""
        <Forms.input field={@form[:label]} label="Bezeichnung" />
        <Forms.input field={@form[:amount]} type="number" />
        """)
        |> LazyHTML.from_fragment()

      assert doc |> LazyHTML.query("#item_label[aria-invalid=true]") |> Enum.count() == 1

      assert doc |> LazyHTML.query("#item_label-error-0") |> LazyHTML.text() =~
               "Muss ausgefüllt werden"

      assert doc |> LazyHTML.query("#item_amount-error-0") |> LazyHTML.text() =~
               "Muss mindestens 0 sein"
    end
  end

  describe "measure_stat/5" do
    test "a dash without unit when unknown, the value in German otherwise" do
      assert CoreComponents.measure_stat("t", "Bilanz", nil, "kWh", 2) ==
               %{id: "t", label: "Bilanz", value: "—", unit: nil}

      assert CoreComponents.measure_stat(nil, "Bilanz", -1.5, "kWh", 2).value == "−1,50"

      assert CoreComponents.measure_stat("t", "Gespart", 1234.5, "€", 2) ==
               %{id: "t", label: "Gespart", value: "1.234,50", unit: "€"}
    end
  end
end
