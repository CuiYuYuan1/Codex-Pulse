#!/usr/bin/env bash
set -euo pipefail

# Contract smoke test for the public Open-Meteo endpoints used by the app.
# It intentionally checks stable fields, not the weather value itself.
command -v curl >/dev/null || { echo "curl is required" >&2; exit 2; }
command -v node >/dev/null || { echo "node is required" >&2; exit 2; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-weather.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

geocode_file="$tmp_dir/geocode.json"
forecast_file="$tmp_dir/forecast.json"
new_york_file="$tmp_dir/new-york.json"

curl -fsS --max-time 20 \
  'https://geocoding-api.open-meteo.com/v1/search?name=%E8%A1%A1%E9%98%B3%E5%B8%82&count=8&language=zh&format=json' \
  -o "$geocode_file"

node - "$geocode_file" > "$tmp_dir/coordinates.txt" <<'NODE'
const fs = require("fs");
const file = process.argv[2];
const payload = JSON.parse(fs.readFileSync(file, "utf8"));
const first = payload?.results?.[0];
if (!first || first.name !== "衡阳市" || first.admin1 !== "湖南" || first.timezone !== "Asia/Shanghai") {
  throw new Error("geocoding contract changed: expected Hengyang/Hunan/Asia-Shanghai");
}
if (!Number.isFinite(first.latitude) || !Number.isFinite(first.longitude)) {
  throw new Error("geocoding response has invalid coordinates");
}
process.stdout.write(`${first.latitude}\n${first.longitude}\n`);
NODE

latitude="$(sed -n '1p' "$tmp_dir/coordinates.txt")"
longitude="$(sed -n '2p' "$tmp_dir/coordinates.txt")"

curl -fsS --max-time 20 \
  "https://api.open-meteo.com/v1/forecast?latitude=${latitude}&longitude=${longitude}&current=temperature_2m,weather_code,is_day&timezone=auto&forecast_days=1" \
  -o "$forecast_file"

node - "$forecast_file" <<'NODE'
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const current = payload?.current;
if (!current || payload.timezone !== "Asia/Shanghai") throw new Error("forecast timezone/current missing");
if (!Number.isFinite(current.temperature_2m)) throw new Error("temperature_2m is not numeric");
if (!Number.isInteger(current.weather_code) || current.weather_code < 0 || current.weather_code > 99) {
  throw new Error("weather_code is outside WMO range");
}
if (current.is_day !== 0 && current.is_day !== 1) throw new Error("is_day must be 0 or 1");
if (current.interval !== 900) throw new Error("current interval is not 15 minutes");
NODE

curl -fsS --max-time 20 \
  'https://api.open-meteo.com/v1/forecast?latitude=40.7128&longitude=-74.0060&current=temperature_2m,weather_code,is_day&timezone=auto&forecast_days=1' \
  -o "$new_york_file"

node - "$new_york_file" <<'NODE'
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.timezone !== "America/New_York") throw new Error("automatic timezone lookup failed");
NODE

echo "Open-Meteo weather contract: PASS"
