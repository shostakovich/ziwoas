defmodule ZiwoasWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

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

    test "keeps German messages given at the validation and fills in their bindings" do
      assert CoreComponents.translate_error(
               {"muss zwischen %{from} und %{to} liegen", [validation: :number, from: 1, to: 9]}
             ) == "muss zwischen 1 und 9 liegen"

      assert CoreComponents.translate_error({"%{unknown} bleibt", []}) == "%{unknown} bleibt"
    end
  end

  describe "input/1" do
    test "shows German errors for a used field" do
      assigns = %{form: item_form(%{"label" => "", "amount" => "-1"})}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input field={@form[:label]} label="Bezeichnung" />
        <CoreComponents.input field={@form[:amount]} type="number" />
        """)

      assert html =~ ~s(<label class="form-label" for="item_label">Bezeichnung</label>)
      assert html =~ ~s(class="form-control is-invalid")
      assert html =~ "muss ausgefüllt werden"
      assert html =~ "muss mindestens 0 sein"
    end

    test "hides errors of a field the user has not touched yet" do
      assigns = %{form: item_form(%{"amount" => "1"})}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input field={@form[:label]} />
        """)

      refute html =~ "invalid"
    end

    test "renders a checkbox as a switch with a hidden false" do
      assigns = %{form: item_form(%{"label" => "a", "enabled" => "true"})}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input field={@form[:enabled]} type="checkbox" switch label="Aktiv" />
        """)

      assert html =~ ~s(class="form-check form-switch mb-3")
      assert html =~ ~s(<input type="hidden" name="item[enabled]" value="false")
      assert html =~ "checked"
      assert html =~ ~s(role="switch")
    end

    test "renders a select with prompt and the chosen option" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <CoreComponents.input
          name="plug"
          value="b"
          type="select"
          prompt="Bitte wählen"
          options={[{"A", "a"}, {"B", "b"}]}
        />
        """)

      assert html =~ ~r/<select name="plug" class="form-select\s*">/
      assert html =~ ~s(<option value="">Bitte wählen</option>)
      assert html =~ ~s(<option selected value="b">B</option>)
    end
  end

  describe "button/1" do
    test "is a button, or a link when it navigates" do
      assigns = %{}

      assert rendered_to_string(~H"""
             <CoreComponents.button variant="outline-danger" size="sm" data-confirm="Sicher?">
               Löschen
             </CoreComponents.button>
             """) =~ ~s(class="btn btn-outline-danger btn-sm" data-confirm="Sicher?")

      assert rendered_to_string(~H"""
             <CoreComponents.button navigate="/">Zurück</CoreComponents.button>
             """) =~ ~s(href="/")
    end
  end

  describe "flash_group/1" do
    test "shows info and error messages as alerts" do
      assigns = %{flash: %{"info" => "Gespeichert.", "error" => "Fehlgeschlagen."}}

      html =
        rendered_to_string(~H"""
        <CoreComponents.flash_group flash={@flash} />
        """)

      assert html =~ "alert-success"
      assert html =~ "Gespeichert."
      assert html =~ "alert-danger"
      assert html =~ "Fehlgeschlagen."
    end
  end
end
