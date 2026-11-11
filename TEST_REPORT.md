# Verification report

**Date:** 2026-11-11 (Africa/Cairo)

## GitHub Actions verification

| Check | Status | Evidence |
|---|---|---|
| Flutter analysis | PASS | Flutter 3.47.0, `flutter analyze --no-fatal-infos`, PR run [43039841500](https://github.com/fatoh112/taskaty/actions/runs/43039841500). |
| Flutter tests | PASS | All 12 Flutter tests passed in PR run [43039841500](https://github.com/fatoh112/taskaty/actions/runs/43039841500). |
| Worker typecheck and tests | PASS | Typecheck, 15 Worker tests, and npm audit passed in the same run. |
| Android debug APK | PASS | `flutter build apk --debug` succeeded with Firebase app variables present and confirmed the APK exists. |
| APK artifact | PASS | [Download taskaty-debug-apk-30](https://github.com/fatoh112/taskaty/actions/runs/43039841500/artifacts/13864603572). Artifact archive: 86,917,263 bytes; SHA-256 `af24aa03393eae1533048a16fe79439d74ecb3a9d135e0618f46f367ccd3ec46`; expires 2026-11-14 14:40:32 UTC. |

This debug APK includes Firebase public app values but has no deployed Worker URL. Firebase runtime startup/auth were not physically tested, and account-backed API use remains unavailable until the Worker is deployed and configured. No release signing key is configured.

## Local checks

| Check | Status | Evidence / limits |
|---|---|---|
| Worker TypeScript typecheck | PASS | `npm run typecheck:worker` completed with `tsc --noEmit`. |
| Worker tests | PASS | `npm run test:worker`: 4 files, 15 tests passed locally. Uses a SQL.js-backed D1-shaped adapter, generated test RSA keys/Firebase JWTs, and mocked FCM/network responses; it is not live FCM verification. |
| Dependency security audit | PASS | `npm audit`: zero known vulnerabilities in the installed npm dependency tree at audit time. Flutter/pub packages were not resolved or scanned locally. |
| Cloudflare Worker build | PASS | `npm --workspace taskpulse-worker run build` completed via the official `cf build` and Cloudflare Vite plugin. A checksum-verified portable Node 24.22.2 was used because the system Node is 24.18. |
| Cloudflare local D1 and Cron | PASS (local emulation) | `cf d1 migrations apply ... --local` applied `0001_initial.sql`; `cf dev` exposed the configured D1 binding and `* * * * *` trigger. Invoking the local scheduled handler returned `outcome: ok`; `/health` then showed a successful heartbeat. This used empty local D1 and no external push. |
| Gradle Wrapper | PASS | Gradle 8.14.6 distribution was downloaded and checksum-verified by the successful CI APK build; the SHA-256 pin matches Gradle's official `.sha256` endpoint. |
| Git whitespace check | PASS | `git diff --check` completed without errors for the latest build and documentation changes. |
| Flutter/Dart analyzer and tests | PASS (CI) | GitHub Actions installed Flutter 3.47.0. `flutter analyze --no-fatal-infos` and all 12 `flutter test` cases passed. Flutter is not installed in the local Windows environment. |
| Android debug APK | PASS (CI) | A Firebase-configured debug APK was built and uploaded by PR run [43039841500](https://github.com/fatoh112/taskaty/actions/runs/43039841500). Release signing is not configured. |
| Cloudflare Free account/deployment | BLOCKED | A read-only Cloudflare connection sees no D1 database for Taskaty and one unrelated Worker. The connection cannot read account subscriptions because it lacks Billing Read scope, so the Free plan cannot be confirmed. No Taskaty resource was created. |
| Firebase project and Android app | PASS | Firebase CLI identified existing project `taskaty-d3042` and registered `com.taskpulse.app` as app ID `1:476661033523:android:69e319439b3b5b6a351146`. Public app config was retrieved. |
| Firebase Email/Password provider | PASS (CLI deployment); UNVERIFIED on device | Official Firebase CLI auth config deployed and reported the provider enabled. Auth flow code is implemented, but real registration, verification, login, and recovery have not been physically exercised. |
| Firebase Spark plan | UNVERIFIED | Firebase CLI does not expose project billing plan. Verify Firebase Console → Project settings → Usage and billing shows Spark and no billing account is linked. No billing changes were made. |
| GitHub Actions Firebase variables | PASS | All four public Firebase Android app values are set as repository Actions variables. The Worker URL remains unset. |
| FCM HTTP v1 and server credentials | BLOCKED | FCM is listed as no-cost on Spark, but project HTTP v1 readiness has not been checked. No service account has been created and no Worker Secret is configured. Cloudflare plan is also unverified. |
| Cloudflare deployment/Cron observation | BLOCKED | The account's Free plan cannot be verified with the available OAuth scope. No Taskaty D1 database or Worker was deployed, so production Cron is unobserved. |
| Physical two-device push acceptance | BLOCKED | Requires a configured Firebase Spark project, Worker deployment and two Android devices with Google Play services. |

## Acceptance criteria

| Item | Status | Evidence / blocker |
|---|---|---|
| A. Two users join one team | PASS (local API harness) | Test creates team and secure invite, joins second Firebase-test user and verifies both memberships through authenticated API calls. |
| B. Assign a four-hour task | PASS (local API harness) | Test creates a 240-minute task assigned to a second team member and checks server-computed due time. |
| C. Both accounts see saved task | PASS (local API harness) | The owner and joined member each list the same stored task from the SQL.js-backed D1 test adapter. |
| D. Completion before deadline creates no overdue event | PASS (local scheduler harness) | Completion is persisted, then scheduled worker logic runs after the deadline and creates no overdue event. |
| E. Cron detects overdue with app closed | PASS (local harness); UNVERIFIED in production | Scheduler tests detect overdue work without an app/client and the load harness simulates delayed Cron runs. A local `cf dev` scheduled-handler smoke check passed, but production Cloudflare Cron has not been deployed or observed. |
| F. Team gets persistent notification records | PASS (local API harness) | Test verifies notification rows are persisted for team members and available from the authenticated notification endpoint. |
| G. Repeated Cron creates one logical overdue event | PASS (local scheduler harness) | Two scheduler runs yield one unique `deadline_events` record and one notification per recipient. |
| H. Unauthorized team access is denied | PASS (local API harness) | An outsider receives `404 TEAM_NOT_FOUND` when listing another team's tasks. |
| I. Arabic voice task after confirmation | UNVERIFIED on device | Parser and Flutter UI tests pass in CI, and the native speech/confirmation flow is implemented. Arabic recognition and confirmation have not been physically tested on an Android device. |
| J. Reconnect restores task data | UNVERIFIED | Foreground refresh polls every 25 seconds and refreshes on resume; no offline cache or offline mutation queue is implemented. Flutter integration/network-recovery tests were not run. |
| K. FCM on two physical devices | BLOCKED | No FCM server credential, deployed Worker, or physical devices configured. FCM mocks do not count as delivery verification. |
| L. Spark and Workers Free only | PASS (architecture/audit) | Source uses Firebase Auth/FCM and Workers/D1/Cron free-plan features only. No paid resources or billing changes were made. Production account plan is unverified. |
| M. No service requires enabling billing | PASS (design audit), account UNVERIFIED | No planned integration requires a paid plan. The account owner must preserve Spark/Workers Free; no account configuration was available to inspect. |
| N. Installable APK builds | PASS (debug) | The Firebase-configured APK built successfully in CI and is available as [artifact 13864603572](https://github.com/fatoh112/taskaty/actions/runs/43039841500/artifacts/13864603572). It is unsigned for release distribution and does not have a Worker URL. |

## Scheduler load measurements

These are repeatable local Node/SQL.js harness results. The test injects mocked FCM responses and measures local Node CPU, elapsed time, SQL calls/statements and row counts. SQL.js does not report Cloudflare Worker CPU, and the test does not measure live D1, Cron scheduling or external FCM delivery.

| Scenario | Observed result |
|---|---|
| 10 overdue tasks, 30 team members, 2 devices/member, one transient FCM 503, repeated Cron | 10 logical events; 300 persistent notifications; 300 mocked recipient deliveries drained in 21 simulated ticks. Deadline detection p50 1 min, p95 2 min, max 2 min. The transient device was retried once. Peak combined D1/Google/FCM subrequests: 46. |
| 100 overdue tasks after a 10-minute scheduler outage, 30 members, 2 devices/member, one transient FCM 503 | 100 logical events; 3,000 persistent notifications and 3,000 mocked recipient records sent in 201 simulated ticks. Maximum due-to-detection delay 29 min; persistent fan-out occurred in the same tick as each event. One device retried once. Peak combined subrequests: 46. |
| Concurrent task completion at exactly the due time and Cron detection | Completion is on time; no overdue event is generated. |

The 10-task run used 196 D1 calls and 554 SQL statements across 21 ticks, returning 1,233 rows and changing 1,687. Its local adapter SQL wall time was 278.67 ms total; per-tick Node CPU p50/p95/max was 31/187/203 ms. The 100-task run used 1,828 D1 calls and 5,408 statements across 201 ticks, returning 12,303 rows and changing 16,773; adapter SQL wall time was 1,640.80 ms total. Per-tick Node CPU p50/p95/max was 16/62/94 ms. These Node numbers must not be compared to Cloudflare's 10 ms CPU allowance; Worker CPU remains unmeasured and deployment is not production-verified.

## Known verification limits

- The local API harness uses SQLite through `sql.js`, not Cloudflare D1; it does not establish D1-specific SQL behavior, Worker CPU use, Cron timing, or service-account account policy.
- FCM tests mock OAuth and HTTP v1 responses. They verify retry logic only, not external delivery.
- Flutter sources and tests compile and pass in GitHub Actions; the local Windows environment still lacks Flutter and the Android SDK.
- Firebase registration/login/verification, FCM token retrieval and delivery, live D1 behavior, native Arabic voice recognition, notification tap routing, and runtime RTL layout still need a deployed backend and/or device verification.
- CI built an APK with Firebase Dart defines after the repository variables were set. The Worker URL remains absent, so the APK cannot connect to the TaskPulse API.
- See [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md) for the limits and quota exhaustion design. Do not treat this implementation audit as production certification.
