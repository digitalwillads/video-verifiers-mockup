#!/bin/zsh
# Publish the mockup to GitHub Pages: commit index.html and push. Pages redeploys on each push to main.
set -euo pipefail
cd "$(dirname "$0")"
log() { print -r -- "[publish $(date +%H:%M:%S)] $*"; }
grep -q '<meta name="robots" content="noindex, nofollow">' index.html || { log "ERROR: index.html has no noindex meta"; exit 1; }
if git diff --quiet -- index.html && git diff --cached --quiet -- index.html; then log "no change to index.html; nothing to publish"; exit 0; fi
log "checking that anyone with each Drive or Docs link can edit (about 20 s)"
./check-links.sh index.html || { log "ERROR: a link failed the check above. Fix its sharing (./check-links.sh --fix, after Will approves) or remove the link."; exit 1; }
log "index.html is $(wc -c < index.html | tr -d ' ') bytes"
git add index.html
git commit -q -m "${1:-Publish a new build of the mockup}" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
log "committed $(git rev-parse --short HEAD)"
t0=$SECONDS; git push -q origin main; log "pushed to origin/main in $((SECONDS - t0)) s"
log "live in about a minute: https://digitalwillads.github.io/video-verifiers-mockup/"
