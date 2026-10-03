# Switches the page look between Clean and Felt for this browser, for good.
class LooksController < ApplicationController
  def update
    look = params[:look]
    return head :bad_request unless Look::Name.valid?(look)

    cookies.permanent[Look::COOKIE] = look
    redirect_back_or_to root_path, status: :see_other
  end
end
