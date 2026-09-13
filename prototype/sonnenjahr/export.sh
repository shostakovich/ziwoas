#!/bin/sh
# PROTOTYPE — exports hourly PV, panel and weather data from a copy of the
# ZiWoAS SQLite database into hours.js, next to sonnenjahr.html.
# Hours are local summer time (UTC+2); the prototype only covered April–September.
set -eu
DB="${1:?usage: export.sh <production.sqlite3> [hours.js]}"
OUT="${2:-$(dirname "$0")/hours.js}"
{
  printf 'window.SITE = '
  sqlite3 -json "$DB" "SELECT lat, lon FROM weather_records LIMIT 1;" | tr -d '[]\n'
  printf ';\n'
  printf 'window.HOURS = '
  sqlite3 -json "$DB" "
WITH w AS (
  SELECT strftime('%Y-%m-%d', timestamp, '+2 hours') d, CAST(strftime('%H', timestamp, '+2 hours') AS INT) h,
         solar, sunshine, cloud_cover
  FROM weather_records WHERE kind='historic'
),
r AS (
  SELECT strftime('%Y-%m-%d', taken_at, '+2 hours') d, CAST(strftime('%H', taken_at, '+2 hours') AS INT) h,
         avg(pv_power_w) pv, count(*) n
  FROM solakon_readings GROUP BY 1,2
),
s AS (
  SELECT strftime('%Y-%m-%d', taken_at, '+2 hours') d, CAST(strftime('%H', taken_at, '+2 hours') AS INT) h,
         avg(pv1_power_w) p1, avg(pv2_power_w) p2, avg(pv3_power_w) p3, avg(pv4_power_w) p4
  FROM solakon_snapshots GROUP BY 1,2
),
a AS (
  SELECT strftime('%Y-%m-%d', bucket_ts, 'unixepoch', '+2 hours') d, CAST(strftime('%H', bucket_ts, 'unixepoch', '+2 hours') AS INT) h,
         sum(energy_delta_wh) ac
  FROM samples_5min WHERE plug_id='bkw' GROUP BY 1,2
)
SELECT w.d, w.h,
       round(w.solar*1000) sol, w.sunshine sun, w.cloud_cover cc,
       CASE WHEN r.n >= 20 THEN round(r.pv) END pv,
       round(s.p1) p1, round(s.p2) p2, round(s.p3) p3, round(s.p4) p4,
       round(a.ac) ac
FROM w LEFT JOIN r ON r.d=w.d AND r.h=w.h LEFT JOIN s ON s.d=w.d AND s.h=w.h LEFT JOIN a ON a.d=w.d AND a.h=w.h
ORDER BY w.d, w.h;"
  printf ';\n'
} > "$OUT"
echo "wrote $OUT"
