defmodule ZiwoasWeb.EconomicsLiveTest do
  use ZiwoasWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ziwoas.{Repo, TestClock}
  alias Ziwoas.Economics.{CostItem, ElectricityPrice}
  alias Ziwoas.EnergyReport.DailyEnergySummary

  @path "/solakon/wirtschaftlichkeit"

  setup do
    TestClock.freeze("2026-10-05T12:00:00+02:00")
    :ok
  end

  defp cost_item!(label, amount, spent_on),
    do: Repo.insert!(%CostItem{label: label, amount_eur: Decimal.new(amount), spent_on: spent_on})

  defp cost_items, do: Repo.aggregate(CostItem, :count)
  defp prices, do: Repo.aggregate(ElectricityPrice, :count)

  defp texts(html, selector),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))

  defp submit_cost(view, attrs),
    do: view |> form("#cost_item_form", cost_item: attrs) |> render_submit()

  defp submit_price(view, attrs),
    do: view |> form("#price_form", electricity_price: attrs) |> render_submit()

  describe "the page" do
    test "lists cost items and prices with their sum", %{conn: conn} do
      cost_item!("Module", "1200.00", ~D[2026-01-05])
      cost_item!("Förderung", "-200.00", ~D[2026-02-01])
      insert_price!("2026-01-01", "0.2902")

      {:ok, _view, html} = live(conn, @path)

      assert texts(html, "h1") == ["Wirtschaftlichkeit"]
      assert texts(html, ".card-title") == ["Stand", "Kostenposten", "Strompreise"]
      assert length(texts(html, ".economics-row")) == 3
      assert html =~ "Förderung"
      assert html =~ "1.000,00 €"
      assert html =~ "−200,00 €"
      assert html =~ "0,2902 €/kWh"
      assert html =~ "05.01.2026"
      assert html =~ "ab 01.01.2026"
    end

    test "keeps the cents of a fractional total", %{conn: conn} do
      cost_item!("Wechselrichter", "699.90", ~D[2026-01-05])
      cost_item!("Montage", "200.00", ~D[2026-01-06])

      assert {:ok, _view, html} = live(conn, @path)
      assert html =~ "899,90 €"
    end

    test "prices self-consumption from the price book, not zero", %{conn: conn} do
      insert_price!("2026-01-01", "0.30")

      Repo.insert!(%DailyEnergySummary{
        date: "2026-04-01",
        produced_wh: 5_000.0,
        consumed_wh: 2_000.0,
        self_consumed_wh: 1_000.0
      })

      assert {:ok, _view, html} = live(conn, @path)
      assert html =~ "0,30 €"
    end

    test "says what is missing, and offers today's date in the forms", %{conn: conn} do
      {:ok, view, html} = live(conn, @path)

      assert html =~ "Noch keine Kostenposten erfasst."
      assert html =~ "Noch kein Strompreis erfasst."
      assert has_element?(view, "#cost_item_form input[type=date][value='2026-10-05']")
      assert has_element?(view, "#price_form input[type=date][value='2026-10-05']")
      assert has_element?(view, "a[href='/solakon']", "Zurück zu PV")
    end

    test "the card on the PV page links here", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/solakon")

      assert {:ok, _view, html} =
               view
               |> element("a", "Kosten erfassen")
               |> render_click()
               |> follow_redirect(conn, @path)

      assert html =~ "Kostenposten"
    end
  end

  describe "a cost item" do
    test "is created from the form, with a flash and an empty form", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      html =
        submit_cost(view, %{
          label: "Wechselrichter",
          amount_eur: "899,90",
          spent_on: "2026-03-01",
          note: "inkl. Montage"
        })

      assert texts(html, "#flash-info") == ["Wechselrichter erfasst"]
      assert html =~ "899,90 €"
      assert html =~ "inkl. Montage"
      assert has_element?(view, "#cost_item_form input[name='cost_item[label]']:not([value])")

      assert [item] = Repo.all(CostItem)

      assert {item.label, item.spent_on, item.note} ==
               {"Wechselrichter", ~D[2026-03-01], "inkl. Montage"}
    end

    test "an invalid one is refused field by field, in German", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      html = submit_cost(view, %{label: "", amount_eur: "viel", spent_on: ""})

      assert texts(html, "#cost_item_form .invalid-feedback") == [
               "Bezeichnung angeben",
               "Betrag als Zahl angeben",
               "Datum angeben"
             ]

      assert texts(html, "#flash-info") == []
      assert cost_items() == 0
    end

    test "is checked while typing, only on the fields touched", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      # The browser marks the fields not yet touched as `_unused_`.
      params = %{
        "label" => "",
        "_unused_label" => "",
        "amount_eur" => "viel",
        "spent_on" => "2026-10-05",
        "note" => "",
        "_unused_note" => ""
      }

      html = view |> element("#cost_item_form") |> render_change(%{"cost_item" => params})

      assert texts(html, "#cost_item_form .invalid-feedback") == ["Betrag als Zahl angeben"]
    end

    test "is deleted after a confirmation, with a flash", %{conn: conn} do
      item = cost_item!("Module", "1200.00", ~D[2026-01-05])
      {:ok, view, _html} = live(conn, @path)

      button =
        element(view, "#cost_item-#{item.id} button[data-confirm='Module wirklich löschen?']")

      html = render_click(button)

      assert texts(html, "#flash-info") == ["Module gelöscht"]
      assert html =~ "Noch keine Kostenposten erfasst."
      assert cost_items() == 0
    end

    test "deleting one that is already gone says so", %{conn: conn} do
      item = cost_item!("Module", "1200.00", ~D[2026-01-05])
      {:ok, view, _html} = live(conn, @path)
      Repo.delete!(item)

      html = view |> element("#cost_item-#{item.id} button") |> render_click()

      assert texts(html, "#flash-error") == ["Kostenposten nicht gefunden"]
    end
  end

  describe "a price" do
    test "is created from the form, rounded like the column", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      html = submit_price(view, %{eur_per_kwh: "0,123456", valid_from: "2026-07-01"})

      assert texts(html, "#flash-info") == ["Preis ab 01.07.2026 erfasst"]
      assert html =~ "0,1235 €/kWh"
      assert [%{valid_from: "2026-07-01"} = price] = Repo.all(ElectricityPrice)
      assert Decimal.equal?(price.eur_per_kwh, Decimal.new("0.12346"))
    end

    test "of zero or less is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)

      html = submit_price(view, %{eur_per_kwh: "0", valid_from: "2026-07-01"})

      assert texts(html, "#price_form .invalid-feedback") == ["Preis muss größer als 0 sein"]
      assert prices() == 0
    end

    test "a second one for the same day is refused", %{conn: conn} do
      insert_price!("2026-07-01", "0.30")
      {:ok, view, _html} = live(conn, @path)

      html = submit_price(view, %{eur_per_kwh: "0,25", valid_from: "2026-07-01"})

      assert texts(html, "#price_form .invalid-feedback") == [
               "Für dieses Datum gibt es bereits einen Preis"
             ]

      assert prices() == 1
    end

    test "is deleted after a confirmation", %{conn: conn} do
      price = insert_price!("2026-07-01", "0.30")
      {:ok, view, _html} = live(conn, @path)

      html =
        view
        |> element(
          "#price-#{price.id} button[data-confirm='Preis ab 01.07.2026 wirklich löschen?']"
        )
        |> render_click()

      assert texts(html, "#flash-info") == ["Preis ab 01.07.2026 gelöscht"]
      assert prices() == 0
    end
  end
end
