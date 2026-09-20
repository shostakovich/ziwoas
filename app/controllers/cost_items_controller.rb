class CostItemsController < ApplicationController
  def create
    result = Economics::Forms::CostItem.new.call(cost_item_params)
    return render_index(cost_errors: result.errors.map(&:text).uniq, status: :unprocessable_entity) if result.failure?

    attrs = result.to_h
    Economics::CostItem.create!(
      label:      attrs[:label],
      amount_eur: Economics::Forms::CostItem.amount(attrs[:amount_eur]),
      spent_on:   Date.iso8601(attrs[:spent_on]).to_s,
      note:       attrs[:note].presence
    )
    redirect_to economics_path
  end

  def destroy
    Economics::CostItem.find_by(id: params[:id])&.destroy
    redirect_to economics_path
  end

  private

  def cost_item_params
    params.fetch(:cost_item, {}).permit(:label, :amount_eur, :spent_on, :note).to_h.symbolize_keys
  end

  def render_index(cost_errors:, status:)
    @overview = Economics::Overview.new.build
    @cost_items = Economics::CostItem.newest_first
    @prices = Economics::ElectricityPrice.newest_first
    @cost_errors = cost_errors
    render "economics/index", status: status
  end
end
