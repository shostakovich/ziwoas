defmodule ZiwoasWeb.EconomicsControllerTest do
  # Mirrors test/controllers/economics_controller_test.rb.
  use ZiwoasWeb.ConnCase

  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Economics.{CostItem, ElectricityPrice}
  alias Ziwoas.EnergyReport.DailyEnergySummary

  setup do
    TestClock.freeze("2026-10-05T12:00:00+02:00")
    :ok
  end

  defp cost_item!(label, amount, spent_on),
    do: Repo.insert!(%CostItem{label: label, amount_eur: Decimal.new(amount), spent_on: spent_on})

  defp price!(valid_from, eur_per_kwh),
    do:
      Repo.insert!(%ElectricityPrice{
        valid_from: valid_from,
        eur_per_kwh: Decimal.new(eur_per_kwh)
      })

  defp page(conn, status \\ 200), do: conn |> html_response(status) |> LazyHTML.from_document()
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()
  defp text(doc, selector), do: doc |> LazyHTML.query(selector) |> LazyHTML.text()

  defp cost_items, do: Repo.aggregate(CostItem, :count)
  defp prices, do: Repo.aggregate(ElectricityPrice, :count)

  defp amount(%{amount_eur: amount}), do: Decimal.to_float(amount)

  test "the page lists cost items and prices with their sum", %{conn: conn} do
    cost_item!("Module", "1200.00", "2026-01-05")
    cost_item!("Förderung", "-200.00", "2026-02-01")
    price!("2026-01-01", "0.2902")

    conn = get(conn, ~p"/solakon/wirtschaftlichkeit")
    doc = page(conn)
    body = html_response(conn, 200)

    assert text(doc, "h1") == "Wirtschaftlichkeit"

    assert doc |> LazyHTML.query(".card-title") |> Enum.map(&LazyHTML.text/1) ==
             ["Stand", "Kostenposten", "Strompreise"]

    assert count(doc, ".economics-row") == 3
    assert body =~ "Förderung"
    assert body =~ "1.000,00 €"
    assert body =~ "−200,00 €"
    assert body =~ "0,2902 €/kWh"
    assert body =~ "05.01.2026"
    assert body =~ "ab 01.01.2026"
  end

  test "a fractional cost total keeps its cents, not just whole euros", %{conn: conn} do
    cost_item!("Wechselrichter", "699.90", "2026-01-05")
    cost_item!("Montage", "200.00", "2026-01-06")

    assert conn |> get(~p"/solakon/wirtschaftlichkeit") |> html_response(200) =~ "899,90 €"
  end

  test "the page prices self-consumption from the price book, not zero", %{conn: conn} do
    price!("2026-01-01", "0.30")

    Repo.insert!(%DailyEnergySummary{
      date: "2026-04-01",
      produced_wh: 5_000.0,
      consumed_wh: 2_000.0,
      self_consumed_wh: 1_000.0
    })

    assert conn |> get(~p"/solakon/wirtschaftlichkeit") |> html_response(200) =~ "0,30 €"
  end

  test "an empty page says what is missing", %{conn: conn} do
    body = conn |> get(~p"/solakon/wirtschaftlichkeit") |> html_response(200)

    assert body =~ "Noch keine Kostenposten erfasst."
    assert body =~ "Noch kein Strompreis erfasst."
  end

  test "a cost item is created from the form", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
        "cost_item" => %{
          "label" => "Wechselrichter",
          "amount_eur" => "899,90",
          "spent_on" => "2026-03-01",
          "note" => "inkl. Montage"
        }
      })

    assert redirected_to(conn) == "/solakon/wirtschaftlichkeit"
    assert [item] = Repo.all(CostItem)
    assert {item.label, amount(item), item.note} == {"Wechselrichter", 899.9, "inkl. Montage"}
    assert item.spent_on == "2026-03-01"
  end

  test "a negative cost item records a subsidy, a blank note none", %{conn: conn} do
    post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
      "cost_item" => %{
        "label" => "Förderung",
        "amount_eur" => "-500",
        "spent_on" => "20260301",
        "note" => " "
      }
    })

    assert [%{note: nil, spent_on: "2026-03-01"} = item] = Repo.all(CostItem)
    assert amount(item) == -500.0
  end

  test "an invalid cost item is refused with its errors", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
        "cost_item" => %{"label" => "", "amount_eur" => "viel", "spent_on" => ""}
      })

    doc = page(conn, 422)
    assert count(doc, ".alert-danger") == 1

    assert text(doc, ".alert-danger") ==
             "Bezeichnung angeben, Betrag als Zahl angeben, Datum angeben"

    assert cost_items() == 0
  end

  test "an amount that is not a finite number is refused", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
        "cost_item" => %{"label" => "Module", "amount_eur" => "1e400", "spent_on" => "2026-03-01"}
      })

    assert html_response(conn, 422) =~ "Betrag als Zahl angeben"
    assert cost_items() == 0
  end

  test "an unparseable date is refused as a date, not silently accepted", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
        "cost_item" => %{"label" => "Module", "amount_eur" => "100", "spent_on" => "not-a-date"}
      })

    assert html_response(conn, 422) =~ "Datum angeben"
    assert cost_items() == 0
  end

  test "an explicitly empty amount is refused as an amount, not a crash", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{
        "cost_item" => %{"label" => "Module", "amount_eur" => nil, "spent_on" => "2026-03-01"}
      })

    assert html_response(conn, 422) =~ "Betrag als Zahl angeben"
  end

  test "a form without its fields answers dry's message once", %{conn: conn} do
    conn = post(conn, ~p"/solakon/wirtschaftlichkeit/kosten", %{})
    assert text(page(conn, 422), ".alert-danger") == "is missing"
  end

  test "a cost item is deleted, a missing one quietly", %{conn: conn} do
    item = cost_item!("Module", "1200.00", "2026-01-05")

    assert conn |> delete(~p"/solakon/wirtschaftlichkeit/kosten/#{item.id}") |> redirected_to() ==
             "/solakon/wirtschaftlichkeit"

    assert conn |> delete(~p"/solakon/wirtschaftlichkeit/kosten/#{item.id}") |> redirected_to() ==
             "/solakon/wirtschaftlichkeit"

    assert conn |> delete(~p"/solakon/wirtschaftlichkeit/kosten/abc") |> redirected_to() ==
             "/solakon/wirtschaftlichkeit"

    assert cost_items() == 0
  end

  test "a price is created from the form, rounded like the column", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/preise", %{
        "electricity_price" => %{"eur_per_kwh" => "0,123456", "valid_from" => "2026-07-01"}
      })

    assert redirected_to(conn) == "/solakon/wirtschaftlichkeit"
    assert [%{valid_from: "2026-07-01"} = price] = Repo.all(ElectricityPrice)
    assert Decimal.to_float(price.eur_per_kwh) == 0.12346
  end

  test "a price of zero or less is refused", %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/preise", %{
        "electricity_price" => %{"eur_per_kwh" => "0", "valid_from" => "2026-07-01"}
      })

    assert html_response(conn, 422) =~ "Preis muss größer als 0 sein"
    assert prices() == 0
  end

  test "a second price for the same day is refused", %{conn: conn} do
    price!("2026-07-01", "0.30")

    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/preise", %{
        "electricity_price" => %{"eur_per_kwh" => "0,25", "valid_from" => "20260701"}
      })

    assert text(page(conn, 422), ".alert-danger") ==
             "Für dieses Datum gibt es bereits einen Preis"

    assert prices() == 1
  end

  test "a price that rounds away in the column is refused as a price, not as a date clash",
       %{conn: conn} do
    conn =
      post(conn, ~p"/solakon/wirtschaftlichkeit/preise", %{
        "electricity_price" => %{"eur_per_kwh" => "0,000004", "valid_from" => "2026-07-01"}
      })

    body = html_response(conn, 422)
    assert body =~ "Preis muss größer als 0 sein"
    refute body =~ "bereits einen Preis"
    assert prices() == 0
  end

  test "a price is deleted", %{conn: conn} do
    price = price!("2026-07-01", "0.30")

    assert conn |> delete(~p"/solakon/wirtschaftlichkeit/preise/#{price.id}") |> redirected_to() ==
             "/solakon/wirtschaftlichkeit"

    assert prices() == 0
  end
end
