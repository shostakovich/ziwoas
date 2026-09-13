require "sun"

class Location
  LAT_RANGE = (-90..90)
  LON_RANGE = (-180..180)

  attr_reader :timezone, :lat, :lon

  def initialize(timezone:, lat: nil, lon: nil)
    @timezone = ActiveSupport::TimeZone[timezone] ||
                raise(ArgumentError, "'#{timezone}' is not a valid IANA timezone")
    @lat = lat
    @lon = lon
  end

  def located? = !@lat.nil? && !@lon.nil?

  def sun = @sun ||= located? ? Sun::Located.new(self) : Sun::Unknown.new

  def timezone_name = @timezone.name
end
