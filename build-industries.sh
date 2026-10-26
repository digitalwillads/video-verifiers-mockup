#!/bin/bash
# Build industries.html (the industry run page) from one run of the video idea verifier.
#
#   ./build-industries.sh <run-dir> ["note line"]
#
# <run-dir> is the folder that `verify video-idea industries ... --out <run-dir>` wrote: it must hold
# lines.json and results.json. The page's data is embedded in the HTML, so the page works offline.
# Logs go to stderr.
set -euo pipefail
cd "$(dirname "$0")"
log() { printf '[build-industries %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

RUN=${1:?usage: ./build-industries.sh <run-dir> ["note line"]}
NOTE=${2:-}
TEMPLATE=industries-template.html
PLACEHOLDER='/*RUN_DATA*/null'
t0=$SECONDS

for f in "$RUN/lines.json" "$RUN/results.json" "$TEMPLATE"; do
  [[ -f $f ]] || { log "ERROR: missing $f"; exit 1; }
done
log "reading $RUN (lines.json $(wc -c < "$RUN/lines.json" | tr -d ' ') bytes)"

# "</" is escaped so a title can never close the page's <script> tag.
data=$(jq -c --arg note "$NOTE" --slurpfile res "$RUN/results.json" -f build-industries.jq "$RUN/lines.json" | sed 's#</#<\\/#g')
lines=$(jq '.lines | length' <<<"$data")
log "data: $lines lines, $(jq -r '[.lines[].outcome] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' <<<"$data"), ${#data} bytes"
if [[ $lines -eq 0 ]]; then log "ERROR: the run has no lines"; exit 1; fi
missing=$(jq '[.lines[] | select(.outcome == "PASS" and .proof == null)] | length' <<<"$data")
if [[ $missing -gt 0 ]]; then log "ERROR: $missing PASS lines have no proof video"; exit 1; fi

template=$(<"$TEMPLATE")
[[ $template == *"$PLACEHOLDER"* ]] || { log "ERROR: $TEMPLATE has no $PLACEHOLDER"; exit 1; }
# Split at the placeholder instead of a pattern replacement, so nothing in the data is read as a pattern.
printf '%s%s%s\n' "${template%%"$PLACEHOLDER"*}" "$data" "${template#*"$PLACEHOLDER"}" > industries.html
log "wrote industries.html ($(wc -c < industries.html | tr -d ' ') bytes) in $((SECONDS - t0)) s"
