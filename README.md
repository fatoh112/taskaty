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

## Security model

The app sends a Firebase ID token in `Authorization: Bearer …` for every API operation. The Worker validates the RS256 signature and Firebase claims, derives the UID from the verified token, and checks team membership from D1 before reading or changing team data. Task deadlines use Worker server time. Notification history is stored per recipient in D1; FCM is a best-effort delivery channel.

## Current state

The repository now contains the Flutter client, Worker API, D1 schema and migrations, Cron/outbox implementation, and automated tests. Worker typechecking, 12 SQL.js API/scheduler tests, Cloudflare `cf build`, and a local `cf dev` D1/Cron smoke check pass. Flutter tests/APK have not been built because Flutter and Android SDK tools are missing. The Firebase project and Cloudflare account are not configured in this checkout, so deployment and physical FCM verification are unverified. See [TEST_REPORT.md](TEST_REPORT.md) for exact boundaries and [docs/](docs/) for design, privacy and operations.
