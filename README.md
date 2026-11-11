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

The public GitHub Actions workflow uses a standard `ubuntu-24.04` runner, runs Flutter analysis/tests and Worker checks, builds a debug APK, and retains the artifact for 3 days. Configure the repository Actions variables `TASKPULSE_API_URL`, `TASKPULSE_FIREBASE_API_KEY`, `TASKPULSE_FIREBASE_APP_ID`, `TASKPULSE_FIREBASE_PROJECT_ID`, and `TASKPULSE_FIREBASE_SENDER_ID` for a configured test build. These are client-side Firebase app settings and the public Worker URL; never put a service-account private key or other backend credential in these variables. If unset, the APK shows the setup-required state.

Latest verified debug APK: [download from run 42948155099](https://github.com/fatoh112/taskaty/actions/runs/42948155099/artifacts/13824326068) (artifact expires 2026-11-14 02:50:14 UTC). See [TEST_REPORT.md](TEST_REPORT.md) for the exact checks and remaining live-service/device verification.

## Security model

The app sends a Firebase ID token in `Authorization: Bearer …` for every API operation. The Worker validates the RS256 signature and Firebase claims, derives the UID from the verified token, and checks team membership from D1 before reading or changing team data. Task deadlines use Worker server time. Notification history is stored per recipient in D1; FCM is a best-effort delivery channel.

## Current state

The repository contains the Flutter client, Worker API, D1 migrations, Cron/outbox implementation, and automated tests. Worker typechecking and all 15 SQL.js API/scheduler tests pass locally; `cf build` and a local `cf dev` D1/Cron smoke check also pass. GitHub Actions run [42948155099](https://github.com/fatoh112/taskaty/actions/runs/42948155099) passed Flutter analysis, all 12 Flutter tests, Worker checks, npm audit, and the Android debug APK build. Firebase is not configured. The read-only Cloudflare connection cannot confirm the account plan, so no production resources were created; deployment and physical FCM verification remain unverified.
