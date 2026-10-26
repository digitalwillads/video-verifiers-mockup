#!/bin/zsh
# Publish the mockup to GitHub Pages: commit the pages and push. Pages redeploys on each push to main.
# The pages: index.html (the mockup) and industries.html (the industry run, made by build-industries.sh).
set -euo pipefail
cd "$(dirname "$0")"
log() { print -r -- "[publish $(date +%H:%M:%S)] $*"; }
PAGES=(index.html industries.html)
SOURCES=(industries-template.html build-industries.sh build-industries.jq)
for p in $PAGES; do
  grep -q '<meta name="robots" content="noindex, nofollow">' "$p" || { log "ERROR: $p has no noindex meta"; exit 1; }
done
changed=$(git status --porcelain -- $PAGES $SOURCES)
if [[ -z $changed ]]; then log "no change to the pages; nothing to publish"; exit 0; fi
log "changed: ${changed//$'\n'/; }"
log "checking that anyone with each Drive or Docs link can edit (about 20 s a page)"
for p in $PAGES; do
  ./check-links.sh "$p" || { log "ERROR: a link in $p failed the check above. Fix its sharing (./check-links.sh --fix, after Will approves) or remove the link."; exit 1; }
done
for p in $PAGES; do log "$p is $(wc -c < "$p" | tr -d ' ') bytes"; done
git add -- $PAGES $SOURCES
git commit -q -m "${1:-Publish a new build of the mockup}" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
log "committed $(git rev-parse --short HEAD)"
t0=$SECONDS; git push -q origin main; log "pushed to origin/main in $((SECONDS - t0)) s"
log "live in about a minute: https://digitalwillads.github.io/video-verifiers-mockup/"
