#!/bin/bash
# Check that anyone who gets a Drive or Docs link from the page can open the item and edit it.
# The page is for outside helpers who have no Drive access of their own,
# so Will set every linked item to "Anyone with the link can edit" (2026-10-26).
# publish.sh runs this check before each push and stops when a link fails.
#
#   ./check-links.sh [page.html]            check every Drive and Docs link (default: index.html)
#   ./check-links.sh --fix [page.html]      give "Anyone with the link" the editor role where it is
#                                           missing, then check again. This changes Drive sharing:
#                                           run it only after Will approves.
#   ./check-links.sh --links [page.html]    print the id and the URL of each Drive and Docs link
#   ./check-links.sh --verdict < item.json  print "<access> <source>" for one Drive files.get reply
#
# Drive is read as will@digitalwillads.com through the Google service account in keymaster.
# Logs go to stderr. The access token is never printed.
set -euo pipefail

WHO=will@digitalwillads.com
API=https://www.googleapis.com/drive/v3/files
FIELDS='name,mimeType,capabilities(canShare),permissions(id,type,role,allowFileDiscovery,permissionDetails)'

# The verdict for one files.get reply: "<access> <source>".
#   access: edit | comment | view | restricted (no link access) | unknown (will@ cannot see the sharing)
#   source: direct (set on the item) | inherited (from a parent folder) | none
VERDICT='
  [.permissions[]? | select(.type == "anyone")] as $a
  | if has("permissions") | not then "unknown none"
    elif ($a | length) == 0 then "restricted none"
    else [$a[].role] as $r
      | (if any($r[]; . == "writer") then "edit" elif any($r[]; . == "commenter") then "comment" else "view" end)
        + (if any($a[]; (.permissionDetails // [{inherited: false}]) | any(.[]; .inherited == false))
           then " direct" else " inherited" end)
    end'

log() { printf '[check-links %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

links() { grep -oE 'https://(drive|docs)\.google\.com/[^"'"'"' <)]+' "$1" | awk '!seen[$0]++'; }
item_id() { sed -E 's#.*/(d|folders)/([^/?]+).*#\2#' <<<"$1"; }

# Prints a Drive access token for $WHO with one scope.
drive_token() {
  local scope=$1 sa email key now hdr clm sig resp token t0=$SECONDS
  sa=$(keymaster secret get GOOGLE_SERVICE_ACCOUNT_JSON)
  email=$(jq -r .client_email <<<"$sa"); key=$(jq -r .private_key <<<"$sa")
  log "minting a Drive token as $WHO (scope ${scope##*/}, service account key ${#key} chars)"
  b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  now=$(date +%s)
  hdr=$(printf '{"alg":"RS256","typ":"JWT"}' | b64)
  clm=$(printf '{"iss":"%s","sub":"%s","scope":"%s","aud":"https://oauth2.googleapis.com/token","iat":%d,"exp":%d}' \
    "$email" "$WHO" "$scope" "$now" $((now + 3600)) | b64)
  sig=$(printf '%s.%s' "$hdr" "$clm" | openssl dgst -sha256 -sign <(printf '%s\n' "$key") -binary | b64)
  resp=$(curl -s https://oauth2.googleapis.com/token \
    -d grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer -d assertion="$hdr.$clm.$sig")
  token=$(jq -r '.access_token // empty' <<<"$resp")
  if [[ -z $token ]]; then
    log "ERROR: no Drive token after $((SECONDS - t0)) s: $(jq -c '{error, error_description}' <<<"$resp")"
    return 1
  fi
  log "token minted in $((SECONDS - t0)) s"
  printf '%s' "$token"
}

# api METHOD PATH [JSON]: calls the Drive API and sets $code and $body. Logs the status and the time.
api() {
  local method=$1 path=$2 data=${3:-} out secs
  local args=(-s -X "$method" -w '\n%{http_code} %{time_total}' -H "Authorization: Bearer $TOKEN")
  if [[ -n $data ]]; then args+=(-H 'Content-Type: application/json' -d "$data"); fi
  log "$method ${path%%\?*}"
  out=$(curl "${args[@]}" "$API/$path")
  body=${out%$'\n'*}
  read -r code secs <<<"${out##*$'\n'}"
  if [[ $code == 2* ]]; then
    log "  -> $code in $secs s"
  else
    log "  ERROR -> $code in $secs s: $(jq -c '.error | {code, message}' <<<"$body" 2>/dev/null || head -c 300 <<<"$body")"
  fi
}

# open_verdict CODE URL: what a person with no Google login gets from a link, from the last
# HTTP code and URL: "opens", "login" or "error-<code>". A private Drive file answers 401 at its own URL.
open_verdict() {
  if [[ $2 == *accounts.google.com* || $1 == 401 || $1 == 403 ]]; then echo login
  elif [[ $1 == 200 ]]; then echo opens
  else echo "error-$1"; fi
}

# Opens the link with no Google login and prints its open_verdict.
opens() {
  local code secs url
  log "  GET with no login ${1%%\?*}"
  read -r code secs url <<<"$(curl -s -L -o /dev/null --max-time 20 -w '%{http_code} %{time_total} %{url_effective}' "$1")"
  log "  GET with no login -> $code in $secs s, ends at ${url%%\?*}"
  open_verdict "$code" "$url"
}

describe() { # access source open
  local text
  case $1 in
    edit) text="anyone with the link can edit" ;;
    comment) text="comment only" ;;
    view) text="view only" ;;
    restricted) text="no link access" ;;
    *) text="sharing hidden from will@" ;;
  esac
  if [[ $1 != edit && $2 == inherited ]]; then text+=" (from a parent folder)"; fi
  case $3 in
    opens) ;;
    login) text+="; asks for a login" ;;
    *) text+="; opens with ${3/-/ }" ;;
  esac
  printf '%s' "$text"
}

check() {
  local page=$1 n=0 fails=0 link id name access source open status t0=$SECONDS
  TOKEN=$(drive_token https://www.googleapis.com/auth/drive.readonly)
  log "check: the Drive and Docs links in $page"
  while read -r link <&3; do
    n=$((n + 1)); id=$(item_id "$link")
    api GET "$id?supportsAllDrives=true&fields=$FIELDS"
    if [[ $code != 200 ]]; then
      fails=$((fails + 1)); printf 'FAIL  %-50s %s\n' "Drive cannot read it ($code)" "$link"; continue
    fi
    name=$(jq -r '.name | gsub("^\\s+|\\s+$"; "")' <<<"$body")
    read -r access source <<<"$(jq -r "$VERDICT" <<<"$body")"
    open=$(opens "$link")
    if [[ $access == edit && $open == opens ]]; then status=PASS; else status=FAIL; fails=$((fails + 1)); fi
    log "  $status: $name | access $access ($source) | no login: $open"
    printf '%s  %-50s %s\n' "$status" "$(describe "$access" "$source" "$open")" "$name"
  done 3< <(links "$page")
  log "check: $n links, $((n - fails)) pass, $fails fail, in $((SECONDS - t0)) s"
  echo "$n links: $((n - fails)) pass, $fails fail"
  [[ $fails == 0 ]]
}

# set_editor ID NAME ACCESS BODY: makes "anyone with the link" an editor of one item.
set_editor() {
  local id=$1 name=$2 access=$3 perm
  perm=$(jq -r '[.permissions[]? | select(.type == "anyone") | select(any(.permissionDetails[]?; .inherited == false))][0].id // empty' <<<"$4")
  if [[ -n $perm ]]; then
    api PATCH "$id/permissions/$perm?supportsAllDrives=true&fields=id,role" '{"role":"writer"}'
  else
    api POST "$id/permissions?supportsAllDrives=true&fields=id,role" '{"type":"anyone","role":"writer","allowFileDiscovery":false}'
  fi
  if [[ $code == 200 ]]; then
    log "  changed: $name ($id) from $access to anyone with the link can edit"
    echo "CHANGED  $name: $access -> anyone with the link can edit"
    return 0
  fi
  log "  ERROR: Drive refused the change on $name ($id): $code"
  echo "ERROR  $name: Drive refused the change ($code)"
  return 1
}

fix() {
  local page=$1 changed=0 errors=0 link id name access source t0=$SECONDS
  local later=()
  TOKEN=$(drive_token https://www.googleapis.com/auth/drive)
  log "fix: give anyone with the link the editor role on the links in $page"
  while read -r link <&3; do
    id=$(item_id "$link")
    api GET "$id?supportsAllDrives=true&fields=$FIELDS"
    if [[ $code != 200 ]]; then errors=$((errors + 1)); continue; fi
    name=$(jq -r '.name | gsub("^\\s+|\\s+$"; "")' <<<"$body")
    read -r access source <<<"$(jq -r "$VERDICT" <<<"$body")"
    case "$access $source" in
      edit\ *) log "  no change: $name already lets anyone with the link edit" ;;
      unknown\ *) log "  ERROR: will@ cannot see or change the sharing of $name; ask its owner"; errors=$((errors + 1)) ;;
      *\ inherited) log "  later: $name gets its link access from a parent folder"; later+=("$link") ;;
      *)
        if [[ $(jq -r .capabilities.canShare <<<"$body") != true ]]; then
          log "  ERROR: will@ cannot share $name"; errors=$((errors + 1))
        elif set_editor "$id" "$name" "$access" "$body"; then changed=$((changed + 1))
        else errors=$((errors + 1)); fi ;;
    esac
  done 3< <(links "$page")
  # An item that inherits its link access can already be fixed through a parent changed above.
  for link in ${later[@]+"${later[@]}"}; do
    id=$(item_id "$link")
    api GET "$id?supportsAllDrives=true&fields=$FIELDS"
    if [[ $code != 200 ]]; then errors=$((errors + 1)); continue; fi
    name=$(jq -r '.name | gsub("^\\s+|\\s+$"; "")' <<<"$body")
    read -r access source <<<"$(jq -r "$VERDICT" <<<"$body")"
    if [[ $access == edit ]]; then
      log "  no change: $name now lets anyone with the link edit through its parent folder"
    elif set_editor "$id" "$name" "$access" "$body"; then changed=$((changed + 1))
    else errors=$((errors + 1)); fi
  done
  log "fix: $changed changed, $errors errors, in $((SECONDS - t0)) s"
  check "$page"
}

main() {
  case "${1:-}" in
    --verdict) jq -r "$VERDICT" ;;
    --links) while read -r link; do printf '%s\t%s\n' "$(item_id "$link")" "$link"; done < <(links "${2:-index.html}") ;;
    --fix) fix "${2:-index.html}" ;;
    -*) log "ERROR: unknown option $1"; exit 2 ;;
    *) check "${1:-index.html}" ;;
  esac
}

# Run only when called, not when the tests source this file.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  cd "$(dirname "$0")"
  main "$@"
fi
