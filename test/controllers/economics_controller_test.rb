require "test_helper"

class EconomicsControllerTest < ActionDispatch::IntegrationTest
  cover "Economics::CostItem*"
  cover "Economics::ElectricityPrice*"
  cover "Economics::Forms*"

  setup do
    DailyEnergySummary.delete_all
    Economics::CostItem.delete_all
    Economics::ElectricityPrice.delete_all
  end

  test "the page lists cost items and prices with their sum" do
    Economics::CostItem.create!(label: "Module", amount_eur: 1_200.00, spent_on: "2026-01-05")
    Economics::CostItem.create!(label: "Förderung", amount_eur: -200.00, spent_on: "2026-02-01")
    Economics::ElectricityPrice.create!(valid_from: "2026-01-01", eur_per_kwh: 0.2902)

    get economics_path

    assert_response :success
    assert_select "h1", text: "Wirtschaftlichkeit"
    assert_select ".card-title", text: /\AKostenposten/
    assert_select ".card-title", text: /\AStrompreise/
    assert_select ".economics-row", 3
    assert_match "Förderung", response.body
    assert_match "1.000,00 €", response.body
    assert_match "0,2902 €/kWh", response.body
  end

  test "an empty page says what is missing" do
    get economics_path

    assert_response :success
    assert_match "Noch keine Kostenposten erfasst.", response.body
    assert_match "Noch kein Strompreis erfasst.", response.body
  end

  test "a cost item is created from the form" do
    assert_difference -> { Economics::CostItem.count }, 1 do
      post cost_items_path, params: { cost_item: { label: "Wechselrichter", amount_eur: "899,90",
                                                   spent_on: "2026-03-01", note: "inkl. Montage" } }
    end

    assert_redirected_to economics_path
    item = Economics::CostItem.last
    assert_equal "Wechselrichter", item.label
    assert_in_delta 899.90, item.amount_eur.to_f
    assert_equal "inkl. Montage", item.note
  end

  test "a negative cost item records a subsidy" do
    post cost_items_path, params: { cost_item: { label: "Förderung", amount_eur: "-500",
                                                 spent_on: "2026-03-01" } }

    assert_redirected_to economics_path
    assert_in_delta(-500.0, Economics::CostItem.last.amount_eur.to_f)
  end

  test "an invalid cost item is refused with its errors" do
    assert_no_difference -> { Economics::CostItem.count } do
      post cost_items_path, params: { cost_item: { label: "", amount_eur: "viel", spent_on: "" } }
    end

    assert_response :unprocessable_entity
    assert_select ".sw-form-errors", 1
    assert_match "Bezeichnung angeben", response.body
    assert_match "Betrag als Zahl angeben", response.body
  end

  test "a cost item is deleted" do
    item = Economics::CostItem.create!(label: "Module", amount_eur: 1_200.00, spent_on: "2026-01-05")

    assert_difference -> { Economics::CostItem.count }, -1 do
      delete cost_item_path(item)
    end

    assert_redirected_to economics_path
  end

  test "a price is created from the form" do
    assert_difference -> { Economics::ElectricityPrice.count }, 1 do
      post electricity_prices_path, params: { electricity_price: { eur_per_kwh: "0,3150",
                                                                   valid_from: "2026-07-01" } }
    end

    assert_redirected_to economics_path
    assert_in_delta 0.3150, Economics::ElectricityPrice.last.eur_per_kwh.to_f
  end

  test "a price of zero or less is refused" do
    assert_no_difference -> { Economics::ElectricityPrice.count } do
      post electricity_prices_path, params: { electricity_price: { eur_per_kwh: "0", valid_from: "2026-07-01" } }
    end

    assert_response :unprocessable_entity
    assert_match "Preis muss größer als 0 sein", response.body
  end

  test "a second price for the same day is refused" do
    Economics::ElectricityPrice.create!(valid_from: "2026-07-01", eur_per_kwh: 0.30)

    assert_no_difference -> { Economics::ElectricityPrice.count } do
      post electricity_prices_path, params: { electricity_price: { eur_per_kwh: "0,25", valid_from: "2026-07-01" } }
    end

    assert_response :unprocessable_entity
    assert_match "bereits einen Preis", response.body
  end

  test "a price that rounds away in the column is refused as a price, not as a date clash" do
    assert_no_difference -> { Economics::ElectricityPrice.count } do
      post electricity_prices_path, params: { electricity_price: { eur_per_kwh: "0,000004",
                                                                   valid_from: "2026-07-01" } }
    end

    assert_response :unprocessable_entity
    assert_match "Preis muss größer als 0 sein", response.body
    assert_no_match(/bereits einen Preis/, response.body)
  end

  test "an amount that is not a finite number is refused" do
    assert_no_difference -> { Economics::CostItem.count } do
      post cost_items_path, params: { cost_item: { label: "Module", amount_eur: "1e400",
                                                   spent_on: "2026-03-01" } }
    end

    assert_response :unprocessable_entity
    assert_match "Betrag als Zahl angeben", response.body
  end

  test "a price is deleted" do
    price = Economics::ElectricityPrice.create!(valid_from: "2026-07-01", eur_per_kwh: 0.30)

    assert_difference -> { Economics::ElectricityPrice.count }, -1 do
      delete electricity_price_path(price)
    end

    assert_redirected_to economics_path
  end
end
