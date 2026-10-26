# Video verifiers mockup

A one-page mockup of three video verifiers (script, research, B-roll): each verifier's rules and a made-up example run. The "Production pipeline" view lists each Digital Will video, its stage, and links to its files.

- Live: https://digitalwillads.github.io/video-verifiers-mockup/
- Edit `index.html`, then run `./publish.sh "what changed"`.
- `industries.html` shows one run of the video idea verifier. To rebuild it from a run folder (the `--out` of `verify video-idea industries`): `./build-industries.sh <run-dir> "one note line"`. It reads the run's `lines.json` and `results.json` and fills `industries-template.html`. Then publish as above.
- Outside helpers use the page, so each Drive and Docs link must let anyone with the link edit. `publish.sh` runs `./check-links.sh` and stops when a link fails.
- `./check-links.sh --fix` gives "Anyone with the link" the editor role where it is missing. It changes Drive sharing, so run it only after Will approves.
- Tests: `tests/check-links.test.sh` (no network).
