defmodule Ziwoas.EconomicsTest do
  use Ziwoas.DataCase

  alias Ziwoas.{Economics, Repo}
  alias Ziwoas.Economics.{CostItem, ElectricityPrice}

  defp errors(changeset), do: Map.new(changeset.errors, fn {field, {msg, _}} -> {field, msg} end)

  defp cost_item!(label, amount, spent_on),
    do: Repo.insert!(%CostItem{label: label, amount_eur: Decimal.new(amount), spent_on: spent_on})

  describe "reading" do
    test "the price book carries every price as a float" do
      insert_price!("2026-07-01", "0.25")
      insert_price!("2026-01-01", "0.2902")

      assert Economics.kwh_prices() == [{~D[2026-01-01], 0.2902}, {~D[2026-07-01], 0.25}]
    end

    test "a stored value with binary noise reads at the column's scale" do
      Repo.query!(
        "INSERT INTO electricity_prices (valid_from, eur_per_kwh, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
        ["2026-01-01", 0.1 + 0.2, "2026-01-01T00:00:00.000000Z", "2026-01-01T00:00:00.000000Z"]
      )

      assert [{_from, 0.3}] = Economics.kwh_prices()
    end

    test "the total cost counts subsidies against the spending, to the cent" do
      assert Economics.total_cost_eur() === 0.0

      cost_item!("Wechselrichter", "699.90", ~D[2026-01-05])
      cost_item!("Montage", "200.10", ~D[2026-01-06])
      cost_item!("Förderung", "-500.00", ~D[2026-02-01])

      assert Economics.total_cost_eur() === 400.0
    end

    test "the lists come newest first" do
      older = cost_item!("Module", "100", ~D[2026-01-05])
      newer = cost_item!("Kabel", "10", ~D[2026-02-01])
      same_day = cost_item!("Stecker", "5", ~D[2026-02-01])
      insert_price!("2026-01-01", "0.30")
      insert_price!("2026-07-01", "0.25")

      assert Enum.map(Economics.cost_items(), & &1.id) == [same_day.id, newer.id, older.id]
      assert Enum.map(Economics.prices(), & &1.valid_from) == [~D[2026-07-01], ~D[2026-01-01]]
    end
  end

  describe "a cost item" do
    test "a new one's form starts on the given day and validates what is typed" do
      assert Ecto.Changeset.get_field(Economics.new_cost_item(~D[2026-10-07]), :spent_on) ==
               ~D[2026-10-07]

      refute Economics.change_cost_item(%{"label" => ""}).valid?
    end

    test "is recorded as typed: a decimal comma, cents, a blank note as none" do
      assert {:ok, item} =
               Economics.create_cost_item(%{
                 "label" => "Wechselrichter",
                 "amount_eur" => "899,904",
                 "spent_on" => "2026-03-01",
                 "note" => "  "
               })

      item = Repo.get!(CostItem, item.id)
      assert {item.label, item.spent_on, item.note} == {"Wechselrichter", ~D[2026-03-01], nil}
      assert Decimal.equal?(item.amount_eur, Decimal.new("899.9"))
    end

    test "may be negative, a subsidy" do
      assert {:ok, item} =
               Economics.create_cost_item(%{
                 "label" => "Förderung",
                 "amount_eur" => "-500",
                 "spent_on" => "2026-03-01"
               })

      assert Decimal.equal?(item.amount_eur, -500)
    end

    test "needs a label, an amount and a date, in German" do
      assert {:error, changeset} =
               Economics.create_cost_item(%{"label" => " ", "amount_eur" => "", "spent_on" => ""})

      assert errors(changeset) == %{
               label: "Bezeichnung angeben",
               amount_eur: "Betrag als Zahl angeben",
               spent_on: "Datum angeben"
             }

      assert Repo.aggregate(CostItem, :count) == 0
    end

    test "refuses what is no amount or date" do
      assert {:error, changeset} =
               Economics.create_cost_item(%{
                 "label" => "Module",
                 "amount_eur" => "viel",
                 "spent_on" => "not-a-date"
               })

      assert errors(changeset) == %{
               amount_eur: "Betrag als Zahl angeben",
               spent_on: "Datum angeben"
             }
    end

    test "refuses an amount the column cannot hold" do
      for amount <- ["1e400", "100000000", "-100000000"] do
        attrs = %{"label" => "Module", "amount_eur" => amount, "spent_on" => "2026-03-01"}
        assert {:error, changeset} = Economics.create_cost_item(attrs)
        assert errors(changeset) == %{amount_eur: "Betrag ist zu groß"}, amount
      end

      attrs = %{"label" => "Module", "amount_eur" => "99999999,99", "spent_on" => "2026-03-01"}
      assert {:ok, _item} = Economics.create_cost_item(attrs)
    end

    test "is deleted by id; a missing or malformed id is no crash" do
      item = cost_item!("Module", "100", ~D[2026-01-05])

      assert {:ok, %CostItem{label: "Module"}} = Economics.delete_cost_item(to_string(item.id))
      assert Economics.delete_cost_item(item.id) == {:error, :not_found}
      assert Economics.delete_cost_item("abc") == {:error, :not_found}
      assert Repo.aggregate(CostItem, :count) == 0
    end
  end

  describe "a price" do
    test "a new one's form starts on the given day and validates what is typed" do
      assert Ecto.Changeset.get_field(Economics.new_price(~D[2026-10-07]), :valid_from) ==
               ~D[2026-10-07]

      refute Economics.change_price(%{"eur_per_kwh" => ""}).valid?
    end

    test "is recorded to the column's five decimals" do
      assert {:ok, price} =
               Economics.create_price(%{
                 "eur_per_kwh" => "0,123456",
                 "valid_from" => "2026-07-01"
               })

      price = Repo.get!(ElectricityPrice, price.id)
      assert price.valid_from == ~D[2026-07-01]
      assert Decimal.equal?(price.eur_per_kwh, Decimal.new("0.12346"))
    end

    test "must be above zero, also after rounding" do
      for typed <- ["0", "-0,30", "0,000004"] do
        assert {:error, changeset} =
                 Economics.create_price(%{"eur_per_kwh" => typed, "valid_from" => "2026-07-01"})

        assert errors(changeset) == %{eur_per_kwh: "Preis muss größer als 0 sein"}, typed
      end
    end

    test "needs a number and a date" do
      assert {:error, changeset} =
               Economics.create_price(%{"eur_per_kwh" => "teuer", "valid_from" => "1. Juli"})

      assert errors(changeset) == %{
               eur_per_kwh: "Preis muss größer als 0 sein",
               valid_from: "Datum angeben"
             }

      assert {:error, changeset} = Economics.create_price(%{})
      assert changeset |> errors() |> Map.keys() |> Enum.sort() == [:eur_per_kwh, :valid_from]
    end

    test "refuses a price the column cannot hold" do
      assert {:error, changeset} =
               Economics.create_price(%{"eur_per_kwh" => "1000", "valid_from" => "2026-07-01"})

      assert errors(changeset) == %{eur_per_kwh: "Preis ist zu hoch"}
    end

    test "one per date" do
      insert_price!("2026-07-01", "0.30")

      assert {:error, changeset} =
               Economics.create_price(%{"eur_per_kwh" => "0,25", "valid_from" => "2026-07-01"})

      assert errors(changeset) == %{valid_from: "Für dieses Datum gibt es bereits einen Preis"}
      assert Repo.aggregate(ElectricityPrice, :count) == 1
    end

    test "is deleted by id" do
      price = insert_price!("2026-07-01", "0.30")

      assert {:ok, _} = Economics.delete_price(price.id)
      assert Economics.delete_price(price.id) == {:error, :not_found}
    end
  end
end
