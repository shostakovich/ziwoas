class ApplicationComponent < ViewComponent::Base
  MONTHS = %w[Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez].freeze

  private

  # SVG coordinates with one decimal: finer than any column these charts draw,
  # and whole numbers stay whole so the markup carries no trailing zeros.
  def number(value)
    rounded = value.round(1)
    rounded == rounded.to_i ? rounded.to_i : rounded
  end
end
