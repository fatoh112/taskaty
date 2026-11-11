# Setup and deployment

This repository is configured for permanent no-cost plans only. Do not attach Cloud Billing, enable Firebase Blaze, or upgrade Cloudflare Workers to Paid. If a quota or account policy blocks setup, leave that integration disabled and report the limit.

## Public GitHub Actions Android build

`.github/workflows/android-build.yml` runs on manual dispatch, relevant pushes to `main`, and pull requests to `main`. It uses the standard `ubuntu-24.04` hosted runner, Java 17, Android SDK API 36, and Flutter stable 3.47.0. GitHub documents standard hosted runners as free on public repositories; this workflow does not use larger runners or a paid build service. The debug APK artifact is retained for 3 days.

The workflow always supports a build without a backend URL. Firebase options are already set as repository **Actions variables** (Settings → Secrets and variables → Actions → Variables):

- `TASKPULSE_API_URL`: deployed HTTPS `workers.dev` API base URL.
- `TASKPULSE_FIREBASE_API_KEY`, `TASKPULSE_FIREBASE_APP_ID`, `TASKPULSE_FIREBASE_PROJECT_ID`, `TASKPULSE_FIREBASE_SENDER_ID`: public settings for the registered Android Firebase app with package `com.taskpulse.app`.

These public app settings are compiled into the APK by design. `TASKPULSE_API_URL` is set to `https://taskpulse-api.sultan-food-internal.workers.dev`. Connected development APK, **DEVELOPMENT TEST ONLY**: CI run [#33](https://github.com/fatoh112/taskaty/actions/runs/43108158419), [artifact 13895247109](https://github.com/fatoh112/taskaty/actions/runs/43108158419/artifacts/13895247109), expires 2026-11-14 22:07:57 UTC. Do not add an FCM service-account JSON/private key, Cloudflare API token, or other server credential to Actions variables or the Android build. Those credentials belong only in Cloudflare Worker Secrets. Artifact access follows GitHub sign-in and repository access rules.

## 1. Firebase Spark

The existing project is `taskaty-d3042` (`taskaty`). The account owner confirmed that it is on Firebase Spark (no-cost). No billing was enabled and no plan was changed. Do not link Cloud Billing or upgrade to Identity Platform.

The CLI registered Android package `com.taskpulse.app` as app ID `1:476661033523:android:69e319439b3b5b6a351146`. `firebase.json` contains the Email/Password provider configuration and `.firebaserc` selects this project. `firebase deploy --only auth --project taskaty-d3042` completed and reported `Auth providers enabled: email/password`. The CLI created a `Default Web App` while provisioning Auth; no duplicate Android app was created. Firebase Auth verification and password-reset emails are implemented in Flutter. Their device flow has not yet been physically tested.

The public Android app values were retrieved with `firebase apps:sdkconfig`. The repository Actions variables `TASKPULSE_FIREBASE_API_KEY`, `TASKPULSE_FIREBASE_APP_ID`, `TASKPULSE_FIREBASE_PROJECT_ID`, `TASKPULSE_FIREBASE_SENDER_ID`, and `TASKPULSE_API_URL` are set. No `google-services.json` is needed: the Flutter app initializes `FirebaseOptions` from these Dart defines. CI run #33 built a connected debug APK using the deployed Worker URL above.

Firebase lists Authentication (most options) and Cloud Messaging as no-cost products on Spark; FCM itself has no charge. The FCM HTTP v1 API is enabled. A narrowly scoped sender service account and token-encryption key are stored as Cloudflare Worker Secrets. A live invalid-token smoke request reached FCM and returned HTTP 400, which verifies the server auth path but not delivery. Never put the private key in this repository, GitHub Actions, APK, or chat. If FCM rejects a valid device token, investigate Spark/project permissions without enabling billing.

## 2. Local Worker development

The Worker uses Cloudflare's recommended `cf` CLI and `cloudflare.config.ts` project format. `cf` is currently beta. The pinned CLI release requires Node `^22.23.0 || ^24.22.0 || ^26.12.0`; this checkout's audited Node 24.18 is too old for that CLI, so install a supported current Node release before invoking it. Follow Cloudflare's current [`cf` setup](https://developers.cloudflare.com/cf/get-started/) and [project command documentation](https://developers.cloudflare.com/cf/projects/).

```powershell
cd backend/worker
npm ci
npm run typecheck
npm test
```

To run Cloudflare's local Worker/D1 emulator after installing the supported Node version:

```powershell
npm run db:migrate:local
npm run dev
```

The local migration script uses the fixed development-only D1 UUID `00000000-0000-4000-8000-000000000003`. `cf dev` uses local D1 and local Cron emulation; it does not deploy or verify real FCM delivery. For offline local tests, FCM requests are mocked.

## 3. Cloudflare Free deployment

The account owner confirmed Cloudflare account `f4c2197713164b02bd5fc0ba861da81d` is on Workers Free ($0). `npx cf auth whoami` verified the authenticated account and valid token. The dedicated D1 database `taskaty-db` (ID `6ef4b4e0-915d-493f-8a4e-2d320aca296c`) was created, and the checked-in initial migration was applied remotely. Worker `taskpulse-api` is deployed at `https://taskpulse-api.sultan-food-internal.workers.dev` with that D1 binding and the `* * * * *` Cron. Current version `909da5a0-0b2c-4c21-91a3-2d89ac759f8a` retains the D1 binding, Firebase project variable, and both FCM Worker Secret bindings; `/health` returned 200 with a fresh scheduler heartbeat.

The previous Worker version produced 189 Cron invocation samples with CPU p50 6.122 ms, p95 11.168 ms, p99 15.167 ms and maximum 16.322 ms; 21 samples exceeded 10 ms. Version #6's 20 idle ticks measured p50 4.590 ms, p95 7.237 ms, maximum 7.562 ms, and zero over-budget runs. A controlled two-task overdue/fanout tick then measured 17.606 ms on #6. Version #7 batches fanout member-page reads/writes and handles no-device or missing-notification outbox rows in the same D1 batch as delivery selection. On #7, the same controlled overdue/fanout workload measured 7.253 ms, a reminder tick measured 5.482 ms, and 20 idle ticks measured p50 4.191 ms, p95 7.659 ms, p99 8.284 ms and maximum 8.440 ms, with no failures or 10 ms overruns. These production checks used no registered device; valid-token FCM delivery CPU remains unmeasured. No plan upgrade is permitted. Cloudflare's [`cf` project documentation](https://developers.cloudflare.com/cf/projects/) covers the existing CLI workflow. Secret names are `FCM_SERVICE_ACCOUNT_JSON` and `FCM_TOKEN_ENCRYPTION_KEY`; values stay in Worker Secrets.

## 4. Android configuration and APK

Install Flutter 3.38.1 or later, Android SDK platform/build tools, and JDK 17. From `apps/android`, fetch packages and run tests, then build with the actual public Firebase app settings and Worker URL:

```powershell
flutter pub get
flutter test
flutter build apk --debug `
  --dart-define=TASKPULSE_API_URL=https://<worker>.<account>.workers.dev `
  --dart-define=FIREBASE_API_KEY=<firebase-web-api-key> `
  --dart-define=FIREBASE_APP_ID=<android-app-id> `
  --dart-define=FIREBASE_PROJECT_ID=<firebase-project-id> `
  --dart-define=FIREBASE_SENDER_ID=<firebase-messaging-sender-id>
```

The debug APK path is `apps/android/build/app/outputs/flutter-apk/app-debug.apk`. Release APKs are debug-signed until the owner configures a private release signing key. Never commit signing material.

## 5. Notifications, voice, and quotas

The Worker persists notification history in D1 before sending FCM. FCM is best-effort: Android power management, connectivity, notification permission, Play services, and force-stop behavior can delay or prevent push delivery. After connectivity returns, foreground polling fetches the authoritative server state; the app does not queue offline edits. A notification tap routes to its task and performs a fresh authenticated fetch.

The voice flow requests Android native speech recognition only after the microphone action. It prefers `ar-EG`; availability, network use, offline recognition, and provider retention depend on the recognizer installed on the device. The transcript is editable and must be confirmed before submission. If recognition is unavailable, users can type the task manually.

Inspect Cloudflare Worker/Cron metrics and D1 row metrics, plus Firebase Authentication and FCM quotas. On exhaustion, let requests fail retryably and wait for reset or reduce use. Do not upgrade. Full limits, request estimates, and quota mitigations are in [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md).
