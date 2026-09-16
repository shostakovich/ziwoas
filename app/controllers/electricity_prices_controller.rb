class ElectricityPricesController < ApplicationController
  def create
    result = Economics::Forms::ElectricityPrice.new.call(price_params)
    errors = result.failure? ? result.errors.map(&:text).uniq : []
    return render_index(price_errors: errors, status: :unprocessable_entity) if errors.any?

    attrs = result.to_h
    price = Economics::ElectricityPrice.new(
      valid_from:  Date.iso8601(attrs[:valid_from]).to_s,
      eur_per_kwh: Economics::Forms::CostItem.amount(attrs[:eur_per_kwh])
    )
    return render_index(price_errors: [ "Für dieses Datum gibt es bereits einen Preis" ],
                        status: :unprocessable_entity) unless price.save

    redirect_to economics_path
  end

  def destroy
    Economics::ElectricityPrice.find_by(id: params[:id])&.destroy
    redirect_to economics_path
  end

  private

  def price_params
    params.fetch(:electricity_price, {}).permit(:eur_per_kwh, :valid_from).to_h.symbolize_keys
  end

  def render_index(price_errors:, status:)
    @overview = Economics::Overview.new.build
    @cost_items = Economics::CostItem.newest_first
    @prices = Economics::ElectricityPrice.newest_first
    @price_errors = price_errors
    render "economics/index", status: status
  end
end
