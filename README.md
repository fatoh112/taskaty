# Taskaty

Taskaty is an Arabic-first collaborative task app. The Android client uses Flutter, Material 3, Riverpod, GoRouter, Firebase Authentication and FCM. A Cloudflare Worker API uses D1 as the authoritative store for teams, tasks, deadlines and notification history.

## Repository layout

- `apps/android/` — Flutter Android application (`com.taskpulse.app`).
- `backend/worker/` — TypeScript Worker API, Firebase token verification and Cron dispatcher.
- `backend/migrations/` — versioned D1 schema migrations.
- `backend/tests/` — Worker and SQL integration tests.
- `docs/` — architecture, privacy and operational notes.
- `FREE_TIER_AUDIT.md` — service-by-service zero-cost audit and quota guardrails.
- `DEPLOYMENT.md` — Firebase, Cloudflare Free and APK setup.
- `TEST_REPORT.md` — real checks and acceptance test status.

## Free-tier policy

Production is designed for Firebase Spark and Cloudflare Workers Free only. It does not use Cloud Functions, Firestore, paid AI, paid speech APIs, paid scheduler products, paid hosting, or a custom domain. Never attach billing to exceed quotas. See [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md) before configuring any service.

## Local development

Install the Flutter stable SDK and Android SDK command-line tools, then follow [DEPLOYMENT.md](DEPLOYMENT.md) for Firebase configuration. Without Firebase project settings and a deployed API URL, the app builds into a setup screen and cannot authenticate or save remote data; it does not simulate those services.

```powershell
cd apps/android
flutter pub get
flutter test
flutter build apk --debug
```

Worker checks:

```powershell
cd backend/worker
npm ci
npm run db:migrate:local
npm run build
npm test
npm run typecheck
```

## Android CI artifact

The public GitHub Actions workflow uses a standard `ubuntu-24.04` runner, runs Flutter analysis/tests and Worker checks, builds a debug APK, and retains the artifact for 3 days. Repository Actions variables contain the public Firebase app settings and deployed Worker URL. These values are compiled into the APK by design; never put a service-account private key or other backend credential in them.

Connected development APK, **DEVELOPMENT TEST ONLY**: CI run [#33](https://github.com/fatoh112/taskaty/actions/runs/43108158419), [download artifact 13895247109](https://github.com/fatoh112/taskaty/actions/runs/43108158419/artifacts/13895247109), expires 2026-11-14 22:07:57 UTC. It contains the deployed API URL and Firebase app configuration. The Worker scheduler is being remeasured on Workers Free; the APK is not a public release or production verification. See [TEST_REPORT.md](TEST_REPORT.md) for current measurements and device-test status.

## Security model

The app sends a Firebase ID token in `Authorization: Bearer …` for every API operation. The Worker validates the RS256 signature and Firebase claims, derives the UID from the verified token, and checks team membership from D1 before reading or changing team data. Task deadlines use Worker server time. Notification history is stored per recipient in D1; FCM is a best-effort delivery channel.

## Current state

The repository contains the Flutter client, Worker API, D1 migrations, Cron/outbox implementation, and automated tests. Worker typechecking and all 17 SQL.js API/scheduler tests pass locally. The account owner confirmed Firebase project `taskaty-d3042` is on Spark and Cloudflare account `f4c2197713164b02bd5fc0ba861da81d` is on Workers Free. Dedicated D1 `taskaty-db` is migrated; Worker `taskpulse-api` is live at [https://taskpulse-api.sultan-food-internal.workers.dev](https://taskpulse-api.sultan-food-internal.workers.dev) with the one-minute Cron trigger. Live `/health`, authenticated registration/login, team membership, task assignment/completion, and assignment notification persistence were exercised. FCM credentials remain Worker Secrets; an invalid-token request reached FCM HTTP v1, but physical delivery is unverified. Cloudflare analytics identified 21 over-budget Cron invocations among 189 baseline samples. Worker version #7 (`909da5a0-0b2c-4c21-91a3-2d89ac759f8a`) passed a 20-tick idle sample (max 8.440 ms), a controlled two-task overdue/fanout tick (7.253 ms), and a reminder tick (5.482 ms). The connected APK is available as run #33's development-only artifact above; run #34 will verify the updated scheduler source. See [TEST_REPORT.md](TEST_REPORT.md) and [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md) for evidence and remaining gates.
