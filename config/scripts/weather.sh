#!/usr/bin/env bash
# weather.sh — weather for the Quickshell dashboard (Open-Meteo, no API key).
#
#   weather.sh            compact JSON (cached for 15 min)
#   weather.sh --force    refresh now
#
# Location / units (optional) in ~/.config/quickshell-weather.env — outside the repo:
#   WEATHER_LAT=27.7172
#   WEATHER_LON=85.3240
#   WEATHER_PLACE="Kathmandu"
#   WEATHER_UNITS=metric        # or imperial
# Without it: Kathmandu, metric.

CONF="$HOME/.config/quickshell-weather.env"
[ -f "$CONF" ] && . "$CONF"
LAT="${WEATHER_LAT:-27.7172}"
LON="${WEATHER_LON:-85.3240}"
PLACE="${WEATHER_PLACE:-Kathmandu}"
UNITS="${WEATHER_UNITS:-metric}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
CACHE="$CACHE_DIR/weather.json"
MAX_AGE=900
mkdir -p "$CACHE_DIR"

fail() { jq -cn --arg e "$1" '{ok: false, error: $e}'; }

if [ "$1" != --force ] && [ -s "$CACHE" ]; then
	age=$(($(date +%s) - $(stat -c %Y "$CACHE")))
	if [ "$age" -lt "$MAX_AGE" ]; then
		cat "$CACHE"
		exit 0
	fi
fi

tu=celsius; wu=kmh
[ "$UNITS" = imperial ] && { tu=fahrenheit; wu=mph; }

FC_URL="https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&timezone=auto&forecast_days=4&temperature_unit=$tu&wind_speed_unit=$wu"
FC_URL+="&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"
FC_URL+="&hourly=temperature_2m,weather_code,precipitation_probability"
FC_URL+="&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max"
AQ_URL="https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$LAT&longitude=$LON&current=us_aqi,pm2_5&timezone=auto"

fc=$(curl -fsS -m 10 "$FC_URL" 2>/dev/null)
if [ -z "$fc" ] || ! echo "$fc" | jq -e '.current' >/dev/null 2>&1; then
	# offline: serve the last good data, marked stale
	if [ -s "$CACHE" ]; then jq -c '. + {stale: true}' "$CACHE"; else fail "no connection to open-meteo.com"; fi
	exit 0
fi
aq=$(curl -fsS -m 8 "$AQ_URL" 2>/dev/null)
echo "$aq" | jq -e '.current' >/dev/null 2>&1 || aq='{}'

out=$(jq -cn --argjson f "$fc" --argjson a "$aq" --arg place "$PLACE" --arg units "$UNITS" '
	($f.current.time[0:13]) as $hour
	| ($f.daily.sunrise[0][11:16]) as $rise
	| ($f.daily.sunset[0][11:16]) as $set
	| {
		ok: true,
		place: $place,
		units: (if $units == "imperial" then "°F" else "°C" end),
		wind_unit: (if $units == "imperial" then "mph" else "km/h" end),
		updated: $f.current.time[11:16],
		now: {
			temp: ($f.current.temperature_2m | round),
			feels: ($f.current.apparent_temperature | round),
			humidity: $f.current.relative_humidity_2m,
			wind: ($f.current.wind_speed_10m | round),
			code: $f.current.weather_code,
			day: ($f.current.is_day == 1)
		},
		today: {
			max: ($f.daily.temperature_2m_max[0] | round),
			min: ($f.daily.temperature_2m_min[0] | round),
			pop: ($f.daily.precipitation_probability_max[0] // 0),
			uv: (($f.daily.uv_index_max[0] // 0) * 10 | round / 10)
		},
		sun: {rise: $rise, set: $set},
		hours: [
			$f.hourly.time | to_entries[] | select(.value[0:13] >= $hour) | .key
		][0:8] | map({
			h: $f.hourly.time[.][11:13],
			temp: ($f.hourly.temperature_2m[.] | round),
			code: $f.hourly.weather_code[.],
			pop: ($f.hourly.precipitation_probability[.] // 0),
			day: (($f.hourly.time[.][11:16]) as $t | $t >= $rise and $t < $set)
		}),
		days: [range(1; ($f.daily.time | length))] | map({
			date: $f.daily.time[.],
			max: ($f.daily.temperature_2m_max[.] | round),
			min: ($f.daily.temperature_2m_min[.] | round),
			code: $f.daily.weather_code[.],
			pop: ($f.daily.precipitation_probability_max[.] // 0)
		}),
		aqi: (if $a.current.us_aqi then {us: ($a.current.us_aqi | round), pm25: ($a.current.pm2_5 | round)} else null end)
	}' 2>/dev/null)

if [ -z "$out" ]; then
	fail "couldn't read the forecast"
	exit 0
fi
echo "$out" >"$CACHE.tmp" && mv "$CACHE.tmp" "$CACHE"
echo "$out"
