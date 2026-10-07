defmodule Ziwoas.Trmnl.Window do
  @moduledoc """
  A widget's time window: `buckets` buckets of `bucket_seconds` that end at
  the first local bucket boundary after `now`. The boundary is floored in
  local time with the offset in force at `now`, so the repeated hour of a
  daylight-saving change still ends after `now`.
  """

  @spec ending_after(DateTime.t(), String.t(), pos_integer, pos_integer) :: {integer, integer}
  def ending_after(now, zone, bucket_seconds, buckets) do
    local = DateTime.shift_zone!(now, zone)
    offset = local.utc_offset + local.std_offset
    local_s = DateTime.to_unix(now) + offset
    end_ts = Integer.floor_div(local_s, bucket_seconds) * bucket_seconds - offset + bucket_seconds
    {end_ts - buckets * bucket_seconds, end_ts}
  end
end
