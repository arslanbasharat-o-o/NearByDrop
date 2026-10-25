# Repository Workflow

- `main` is canonical; `.github/workflows/sync-beta.yml` mirrors its commits to `beta` using fast-forwards only.
- The maintainer may push directly to `main`; no pull request is needed for maintainer changes.
- Do not force-push or delete `main` or `beta`. If `beta` diverges, reconcile it before syncing.

# Commit Messages

- Keep subjects to 5–10 words and under 60 characters.
- Make each subject witty and specific about the change; avoid repeated or generic jokes.
