# Setup and deployment

This repository is configured for permanent no-cost plans only. Do not attach Cloud Billing, enable Firebase Blaze, or upgrade Cloudflare Workers to Paid. If a quota or account policy blocks setup, leave that integration disabled and report the limit.

## 1. Firebase Spark

1. Create/select a Firebase project that remains on Spark, with no Cloud Billing account linked.
2. Register Android package `com.taskpulse.app`.
3. Enable Firebase Authentication email/password. Configure verification and password reset templates.
4. Enable Firebase Cloud Messaging. Android push requires a device/emulator with Google Play services and notification permission.
5. In Firebase Project settings, copy the public app values: Web API key, Android App ID, Project ID and sender ID. The Flutter client initializes Firebase from Dart defines; `google-services.json` is not required by this project.
6. For server push, use the project's service account only if the account lets you create/use it on Spark. Grant only the FCM send permission. Never copy its private key into this repository, APK, or chat. If key creation is blocked by policy, report that blocker and keep push sending unconfigured; do not change plans.

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

First authenticate with the project owner's Cloudflare account and confirm the dashboard still shows the Free plan. These are account-owner interactive actions; do not provide credentials in chat.

```powershell
cd backend/worker
npx cf auth login
npx cf auth whoami
npx cf deploy --dry-run
```

Create a D1 database named `taskpulse-db` on that same Free account. Use the documented CLI discovery flow (`npx cf cli search "create a D1 database"`, then inspect the result with `npx cf schema ...`) to confirm the exact current command/options. Save its database ID as the process environment variable `TASKPULSE_D1_ID` for subsequent `cf` commands; the config binds it as `DB`. Never set or use an upgrade plan.

Before the first deployment, apply the checked-in schema to the remote database:

```powershell
npx cf d1 migrations apply <D1_DATABASE_ID> --dir ../migrations
```

Set `FIREBASE_PROJECT_ID` in the PowerShell process environment for `cloudflare.config.ts` to expose it as a non-secret text binding. Set these two private values as Worker Secrets with the current `cf` secret command (discover and inspect it using `npx cf cli search "set a Worker secret"` and `npx cf schema ...`):

- `FCM_SERVICE_ACCOUNT_JSON`: the service account JSON authorized for FCM HTTP v1.
- `FCM_TOKEN_ENCRYPTION_KEY`: base64 encoding of 32 cryptographically random bytes, used to encrypt device tokens at rest.

Keep secret values out of shell history, source, logs, and Git. Then deploy:

```powershell
npx cf deploy
```

The config provisions one D1 binding, `workers.dev`, and the `* * * * *` Cron trigger. Confirm the account remains Free, apply the migration before users access the API, then record the deployed `https://<worker>.<account>.workers.dev` URL. Cloudflare's current [CLI deployment guide](https://developers.cloudflare.com/cf/projects/) describes auth, dry runs and deploy behavior. Cron has only 10 ms CPU per Free invocation, so real account emulation/metrics must establish whether FCM signing and current bounded processing fit before production use.

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
