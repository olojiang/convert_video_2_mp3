# Repository Delivery Preferences

- After app code changes, run the release build script when feasible so `/Applications/ConvertVideo2MP3.app` is updated, not only the debug build.
- When the user asks for completion of a code change, prefer updating GitHub after verification: commit, push to `origin`, and update GitHub Releases with `gh` when release artifacts are produced.
- Use `scripts/build_release.sh` as the canonical local release path because it runs tests, builds the release app bundle, signs it locally, creates `dist/ConvertVideo2MP3.zip`, and installs the app into `/Applications`.
- If a GitHub push or release update cannot be completed, report the exact blocker and leave the local build/install state clear.
