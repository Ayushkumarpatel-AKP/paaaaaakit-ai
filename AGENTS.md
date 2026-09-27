# AGENTS.md

Guidance for AI agents (and humans) working in this repo.

## Git sync — commit and push automatically

This repo is configured for **auto-sync**. The rules:

1. **After every code change, commit it.** Do not leave edits uncommitted.
2. A `post-commit` hook (`.githooks/post-commit`, enabled via `git config core.hooksPath .githooks`) pushes the current branch to its upstream on every commit. You do **not** need to run `git push` yourself.
3. Before committing, run `git status` and `git diff` and stage only the intended files. Never commit secrets — `OPENAI_API_KEY` and friends are read from the environment (see `backend/config.py`), and `.env*` is gitignored.
4. Write commit messages that match existing style: imperative, short subject line, a blank line, then a body when the change needs explaining.

### If the push fails

The hook retries 3 times, then prints:

```
post-commit: AUTO-PUSH FAILED -- your commit is local only.
```

That means **the commit is safe locally but not on GitHub.** Re-run `git push origin <branch>` once connectivity is back, and tell the user the push is still pending. Never report work as "pushed" without seeing `main -> main` succeed.

## Repo layout

| Path | What it is |
|---|---|
| `lib/` | Flutter app (screens, widgets, services, theme) |
| `backend/` | FastAPI service — routers, physics services, LLM proxy |
| `android/` | Android host project (Gradle, Kotlin) |
| `test/` | Flutter widget tests |
| `PackIT_AI_v1.0.apk` | Committed release build, ~47.8 MB |

## Build & test

```bash
flutter analyze                                   # static analysis
flutter test                                      # widget tests
cd backend && python -m pytest                    # backend tests
flutter build apk --release                       # produces PackIT_AI_v1.0.apk
```

No Android device is currently attached — `flutter devices` shows only Windows, Chrome, and Edge. There are no emulators installed, so an APK can be compiled but not installed automatically.
