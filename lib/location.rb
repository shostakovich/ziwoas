require "sun"

# Where the house stands: its time zone and, once configured, its coordinates.
# The one thing the sun, the weather station and every local clock hour are read
# against. A location without coordinates is complete — the clock still runs —
# but then no sun position exists and no weather is fetched.
#
# It carries the zone as an object rather than a name, so the zone is parsed
# once here instead of in every reader, and it picks the sun adapter itself:
# `#sun` answers with the located sun or with the unknown one. That is the only
# place in the codebase that decides between the two, which is why nothing
# downstream asks whether coordinates were configured.
class Location
  LAT_RANGE = (-90..90)
  LON_RANGE = (-180..180)

  attr_reader :timezone, :lat, :lon

  # timezone is an IANA identifier; lat and lon come as a pair or not at all.
  def initialize(timezone:, lat: nil, lon: nil)
    @timezone = ActiveSupport::TimeZone[timezone] ||
                raise(ArgumentError, "'#{timezone}' is not a valid IANA timezone")
    @lat = lat
    @lon = lon
  end

  def located? = !@lat.nil? && !@lon.nil?

  def sun = @sun ||= located? ? Sun::Located.new(self) : Sun::Unknown.new

  # The zone's name, for the few interfaces that insist on a string.
  def timezone_name = @timezone.name
end
