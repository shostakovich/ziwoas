defmodule Ziwoas.Trmnl.Window do
  @moduledoc "Floored with the offset in force at `now`, so the repeated DST hour still ends after `now`."

  @spec ending_after(DateTime.t(), String.t(), pos_integer, pos_integer) :: {integer, integer}
  def ending_after(now, zone, bucket_seconds, buckets) do
    local = DateTime.shift_zone!(now, zone)
    offset = local.utc_offset + local.std_offset
    local_s = DateTime.to_unix(now) + offset
    end_ts = Integer.floor_div(local_s, bucket_seconds) * bucket_seconds - offset + bucket_seconds
    {end_ts - buckets * bucket_seconds, end_ts}
  end
end
