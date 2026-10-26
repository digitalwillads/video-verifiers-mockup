#!/bin/bash
# Tests for check-links.sh, built from the real case of 2026-10-26: 4 of the 19 Drive links on the
# pipeline page let anyone with the link view but not edit, and the session first said that the links
# opened only for people with access. Each real fixture is the Drive files.get reply of that day,
# with no email addresses. The tests use no network.
set -euo pipefail
cd "$(dirname "$0")/.."
pass=0; fail=0

expect() { # name expected actual
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); echo "ok    $1"
  else fail=$((fail + 1)); printf 'FAIL  %s\n      expected: %s\n      got:      %s\n' "$1" "$2" "$3"; fi
}
verdict() { ./check-links.sh --verdict < "tests/fixtures/$1.json"; }

expect "channel folder: view only, set on the folder" "view direct" "$(verdict channel-folder)"
expect "Draft 2 file: view only, set on the file" "view direct" "$(verdict draft-2-file)"
expect "Furniture Store folder: view only, from its parent folder" "view inherited" "$(verdict furniture-store-folder)"
expect "FacePics folder: view only, from its parent folder" "view inherited" "$(verdict face-pics-folder)"
expect "crypto final export: anyone with the link can edit" "edit inherited" "$(verdict crypto-final-export)"
expect "made-up: a file with no link access" "restricted none" "$(verdict restricted)"
expect "made-up: a file whose sharing will@ cannot see" "unknown none" "$(verdict sharing-hidden)"

expect "links: each Drive and Docs link once, no YouTube link" \
"1l5ZPpavLYYXS-FG5rqBEfMdCPnPBEkA7	https://drive.google.com/drive/folders/1l5ZPpavLYYXS-FG5rqBEfMdCPnPBEkA7
1yu5aKBCmT4WJVnCOxuWf7275o3hNcUbc	https://drive.google.com/file/d/1yu5aKBCmT4WJVnCOxuWf7275o3hNcUbc/edit
1VTSDIpMhC-j7nYwqeD_uD0RDmWo62o_fmK697hmbDio	https://docs.google.com/document/d/1VTSDIpMhC-j7nYwqeD_uD0RDmWo62o_fmK697hmbDio/edit" \
"$(./check-links.sh --links tests/fixtures/page.html)"

# What a person with no Google login got from a private item of each link shape (2026-10-26).
source ./check-links.sh
expect "no login: a private Drive file answers 401" "login" \
  "$(open_verdict 401 https://drive.google.com/file/d/PRIVATE_FILE_ID/edit)"
expect "no login: a private Doc answers 401" "login" \
  "$(open_verdict 401 https://docs.google.com/document/d/PRIVATE_DOC_ID/edit)"
expect "no login: a private folder ends at the sign-in page" "login" \
  "$(open_verdict 200 https://accounts.google.com/v3/signin/identifier)"
expect "no login: a shared folder opens" "opens" \
  "$(open_verdict 200 https://drive.google.com/drive/folders/1l5ZPpavLYYXS-FG5rqBEfMdCPnPBEkA7)"
expect "made-up: a missing file" "error-404" "$(open_verdict 404 https://drive.google.com/file/d/MISSING_ID/edit)"

echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
