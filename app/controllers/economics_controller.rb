# The Kostenposten and Strompreise behind the Wirtschaftlichkeit card. Editing is
# deliberately absent: with a handful of rows, deleting and re-entering is
# shorter than a form that has to remember which row it belongs to.
class EconomicsController < ApplicationController
  def index
    @overview = Economics::Overview.new.build
    @cost_items = Economics::CostItem.newest_first
    @prices = Economics::ElectricityPrice.newest_first
  end
end
