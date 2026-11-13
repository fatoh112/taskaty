# Taskaty verification report

**Updated:** 2026-11-13 (Africa/Cairo)
**Scope:** Connected Flutter Web acceptance, native Android APK delivery, Cloudflare Free CPU reduction, live Cron, D1 usage, and notifications. No service was upgraded and no billing was activated.

## Android UI quality pass (2026-11-13)

**Confirmed dropdown root cause:** `SelectTeamCard` used `DropdownButton<Team>` and stored a `Team` object in `activeTeamProvider`. `Team` has no value equality, so a refresh that decoded a new object for the same team ID left the dropdown value unmatched by its refreshed items. Flutter then raised the reported “exactly one item” assertion. The selector now uses unique non-empty team IDs as dropdown values, and `teamsProvider` synchronizes the active state to the canonical object returned by the latest server list. Deleted selections resolve to the first current team or `null`; the widget itself does not mutate provider state during build.

**Overflow evidence:** The reported `BOTTOM OVERFLOWED BY 93572 PIXELS` was not accompanied by an Android stack trace or a native screenshot in this checkout. Its exact source is therefore **UNVERIFIED**, and it cannot safely be attributed only to the dropdown error screen. An independent dashboard test did reproduce a real 11-pixel bottom overflow in a statistics tile at 320×568, Arabic, dark theme, text scale 1.0. The tile's fixed 112-pixel height was too short for Arabic font metrics. Its height now expands with text scale from 136 pixels, and the dashboard matrix passes. The task list's fixed-height `Column` was replaced with one refreshable sliver scroll view, while task cards constrain long titles, assignees, and countdowns. Automated Flutter widget rendering reported no exceptions or layout overflows across these cases:

- Task list and shell: 320×568, 360×640, 393×852, 412×915, 915×412 landscape, and 800×1024 tablet; Arabic and English; text scale 1.0, 1.3, and 1.6; light and dark themes (72 combinations).
- Dashboard summary/statistics: 320×568, 393×852, and 800×1024; Arabic and English; text scale 1.0 and 1.6; light and dark themes (24 combinations).
- Login and team onboarding: 320×568, 393×852, and 800×1024; Arabic and English; text scale 1.0 and 1.6; simulated keyboard inset on and off (48 combinations).
- Team selector regression coverage: stale same-ID objects, provider synchronization after refresh, deleted selection, duplicate and empty IDs, no teams, selecting a team, and task-list refresh after switching teams.

The full Flutter test suite passed **23 tests** across 144 responsive combinations. `flutter analyze --no-fatal-infos` exited 0 with **91 info-level lints/deprecation notices and no warnings or errors**. `flutter pub get` passed. `flutter build web --release` passed in 102.4 seconds as a compatibility build; it was not a connected browser acceptance run. Worker typecheck passed and its five test files reported 20 passing tests. No backend source or production data changed.

The only locally visible Flutter devices were Windows, Chrome, and Edge. Native Android install, logcat review, system-bar/keyboard behavior on an actual device, microphone recognition, and physical screenshots are **UNVERIFIED**. Android APK build and signature checks are pending the next GitHub Actions run after this UI change is pushed.

## Native Android APK delivery (2026-11-13)

The APKs were built by GitHub Actions run [#43425005303](https://github.com/fatoh112/taskaty/actions/runs/43425005303) from PR head `71f24b4eb09fb6c1c301c006dfde7dee4a81e19c`. The run completed successfully, validated the APK signatures and compiled manifest metadata, then uploaded artifact `taskaty-android-full-apk-42`. Download it from [the GitHub Actions artifact](https://github.com/fatoh112/taskaty/actions/runs/43425005303/artifacts/14037491075); it expires at **2026-11-16 12:33:21 UTC**. The ZIP is 117,228,695 bytes.

| Artifact file | Status | Size | SHA-256 |
|---|---|---:|---|
| `taskaty-android-debug.apk` | PASS | 167,666,289 bytes | `a1626c3eb7776f3c1fedec3b1492ded384755f10256470a276f9358ac96fd312` |
| `taskaty-android-release-debug-signed.apk` | PASS (release mode, debug signed) | 61,282,729 bytes | `80826a8f9cb723eba9c99060782d878d3c4ff90227c2983db56922f4303a7b2a` |

Both APKs declare package `com.taskpulse.app`, version `1.0.0+1`, and minimum SDK 24 (Android 7.0). `apksigner` verified APK Signature Scheme v2 and one signer for each APK. The archived checksum file matches SHA-256 values independently computed after downloading and extracting the uploaded artifact. The run validated that the existing GitHub Actions variables match Firebase project `taskaty-d3042`, Android app ID `1:476661033523:android:69e319439b3b5b6a351146`, sender ID `476661033523`, and the deployed HTTPS Worker URL; those values were passed to the build via a temporary Dart-defines file. No service-account or signing private key was placed in the APK.

Flutter analysis, 13 Flutter tests, Worker typecheck, 20 Worker tests, and `npm audit --audit-level=high` all passed in the successful CI run. Local Flutter analysis reported 48 informational lints/deprecations and no warnings/errors. `flutter build web --release` also succeeded locally. The first validation attempts exposed that `flutter_local_notifications` 22.3.3 requires API 24; the app's declared minimum was corrected from 23 to 24, and the final build verified API 24 in both compiled manifests.

No Android SDK/ADB, emulator, or physical Android device was available locally (`flutter devices` listed only Windows, Chrome, and Edge). Therefore APK installation, Android Firebase login, Android task mutations, microphone speech recognition, notification tap routing, FCM token registration, offline recovery, and physical push delivery remain **UNVERIFIED on Android**. The real Firebase authentication, API, task, D1 persistence, notification-history, and cross-team workflows listed below were tested through Flutter Web; they are not evidence of Android runtime or physical push verification. The Worker `/health` endpoint returned HTTP 200 on 2026-11-13 12:22:59 UTC, with `status: ok`, Cron last finished at 12:22:54 UTC, and `lastErrorCode: null`.

The release-mode APK currently uses the generated Android debug signing key and is not production-signed. No persistent release keystore was created. Secure key-generation and GitHub Actions secret handling steps are documented in [docs/ANDROID_RELEASE_SIGNING.md](docs/ANDROID_RELEASE_SIGNING.md); owner approval is still needed before creating the persistent key.

## Resumed Flutter Web acceptance (2026-11-13)

Tests used two existing, real Firebase email/password accounts on the registered Web app and the deployed Worker. Their temporary QA team records were queried from the production D1 database read-only before cleanup. The owner’s personal Firebase account was not used.

| Check | Status | Evidence |
|---|---|---|
| Firebase email verification and fresh login | PASS | The earlier real Gmail verification flow succeeded. The assignee account was signed out from Flutter Web, used a real Firebase password-reset email, and signed in again successfully. Its authenticated Worker `/v1/teams` request returned 200 after login. |
| Team creation and invitation join | PASS | The two existing authenticated accounts created a QA team and joined it with a one-use invitation through the app. The team and memberships were stored in D1. |
| Create, assign, start, and complete | PASS | The creator submitted a four-hour task through Flutter Web to the second account. The assignee opened its details, started and completed it. A browser refresh restored `completed` status. Activity history displayed created, started, and completed entries with server timestamps. |
| Assignment and completion notification history | PASS | The assignee saw the assignment entry and later the completion entry in Flutter Web. After a page refresh, the notification screen still listed both, alongside team creation/join entries. Authenticated Worker `GET /v1/notifications` returned the same records. A read-only Cloudflare D1 query found the completed task row and assignment/completion notification rows for the correct team member. |
| Cross-team task and notification isolation | PASS | A real authenticated account that was not a member of a separate QA team received `404 TEAM_NOT_FOUND` for that team's task list and a task detail request. Its notification feed contained no record from that team, and trying to mark that team's notification read returned `404 NOTIFICATION_NOT_FOUND`. The owner account could read the isolated team task. |
| Verified-token regression | PASS | Following fresh login, the verified account's authenticated team-list requests returned 200. A malformed/expired bearer token returned one `401 INVALID_TOKEN`. The Flutter retry branch is bounded to a single forced token refresh and only the `EMAIL_NOT_VERIFIED` response for an already verified local Firebase user. |
| Browser CORS | PASS | `OPTIONS` from `http://127.0.0.1:5173` returned 204 with the exact allowed origin; authenticated `GET /v1/teams` returned 200 with that origin. An unrelated origin's preflight returned 403 without `Access-Control-Allow-Origin`. |
| API/scheduler health | PASS | Production `/health` returned 200/`ok`, a recent scheduler finish (28 seconds before the check), and no scheduler error. |
| Browser console/network | PASS | On the latest authenticated page refresh, Playwright recorded no page exceptions, console errors, failed requests, or local-origin HTTP errors. |
| D1 persistence | PASS | Task status and completion time plus its notification rows were read from `taskaty-db` after browser reload. No local mock backend was involved. |
| Browser push | UNVERIFIED | The public VAPID key is absent (`TASKATY_WEB_VAPID_KEY` unset); Settings correctly disables browser registration. No Web FCM token or actual browser push was demonstrated. Persistent in-app notification history works. |

### Automated regression results

| Check | Status | Result |
|---|---|---|
| Flutter analysis | PASS | `flutter analyze --no-fatal-infos` exited 0. It reported 48 informational lints/deprecations; no warnings or errors. Plain `flutter analyze` exits 1 because the SDK treats those info-level findings as fatal by default. |
| Flutter tests | PASS | `flutter test`: 13 tests passed, including Arabic parser, task form validation, and RTL widget rendering. |
| Flutter Web build | PASS | `flutter build web --release --dart-define-from-file=../../.taskaty-local/web-defines.json` built `apps/android/build/web`. Wasm dry run succeeded; no APK was built. |
| Local Web launcher configuration | PASS | `scripts/run-web.ps1 -ConfigureOnly` exited 0 and generated only the ignored local public-config file and Firebase messaging service worker. |
| Worker typecheck | PASS | `npm run typecheck` exited 0. |
| Worker tests | PASS | `npm test`: 5 files, 20 tests passed, including exact-origin preflight, rejected foreign origins, and CORS on authenticated API errors. |
| Automatic Android CI for this push | CANCELLED before APK | GitHub queued [run #43415666260](https://github.com/fatoh112/taskaty/actions/runs/43415666260); it was cancelled during Flutter setup under the Web-only no-APK instruction. The APK build and upload steps were skipped. The local checks above were run directly and passed. |
| Current native Android APK CI | PASS | [Run #43425005303](https://github.com/fatoh112/taskaty/actions/runs/43425005303) built and validated universal debug and release-mode APKs from PR head `71f24b4`; see the Android delivery section above. |

The two disposable QA Firebase accounts were deleted after real password reauthentication. Their two exact QA teams were removed from D1; cascading cleanup removed invitations, tasks, activity, and notifications. QA-specific API rate-limit buckets and local app/Firebase action-site data in both disposable browser profiles were also cleared. A read-only follow-up query returned zero QA team, user, task, notification, activity, invitation, device-token, and rate-limit rows. The owner's personal Firebase account and unrelated production data were not changed.

## Deployment and account state

| Check | Status | Evidence |
|---|---|---|
| Cloudflare plan | PASS (owner confirmation) | Owner confirmed account `f4c2197713164b02bd5fc0ba861da81d` is Workers Free ($0). `cf auth whoami` reported authenticated and token valid for that account. |
| Firebase plan | PASS (owner confirmation) | Owner confirmed Firebase project `taskaty-d3042` is Spark. No Blaze or Cloud Billing was enabled. |
| D1 database and migration | PASS | Dedicated `taskaty-db` (`6ef4b4e0-915d-493f-8a4e-2d320aca296c`) contains the checked-in migration. No unrelated database was changed. |
| Worker version and Cron | DEPLOYED | `taskpulse-api` is live at [https://taskpulse-api.sultan-food-internal.workers.dev](https://taskpulse-api.sultan-food-internal.workers.dev), current version `909da5a0-0b2c-4c21-91a3-2d89ac759f8a`, D1 binding retained, and Cron remains `* * * * *`. `cf workers versions get` confirmed both FCM secret bindings and the Firebase project variable remain configured. |
| Production health | PASS | `/health` returned 200 with `status: ok`, recent scheduler start/finish timestamps, and no scheduler error. |
| Existing live account/API smoke | PASS (previous scheduler run) | Two temporary Firebase email/password accounts exercised team/task APIs. The resumed browser acceptance above additionally verified the user-facing email-verification and password-reset flows. |
| Assignment notification history | PASS (live Web and D1) | Assignment and completion notifications appeared in the assignee's browser history after refresh and matched read-only D1 rows. |
| FCM server authentication | PASS (previous run); delivery UNVERIFIED | Worker credentials are secrets only. An intentionally invalid token reached FCM HTTP v1 and returned HTTP 400, confirming OAuth/server connectivity but not delivery. No valid device token or physical push receipt is available. |
| Connected debug and release-mode APKs | PASS (development artifacts) | CI run [#43425005303](https://github.com/fatoh112/taskaty/actions/runs/43425005303) built both APKs with the validated Firebase settings and deployed `TASKPULSE_API_URL`; download [artifact 14037491075](https://github.com/fatoh112/taskaty/actions/runs/43425005303/artifacts/14037491075), expires 2026-11-16 12:33:21 UTC. Release-mode APK uses the debug signing key; physical-device verification is still unavailable. |
| Physical Android verification | UNVERIFIED | No Android device/ADB is available locally. Native Arabic speech, real app login, notification taps, offline recovery, force-stop behavior, and successful FCM delivery have not been physically tested. |
| Pull request | PASS | PR [#1](https://github.com/fatoh112/taskaty/pull/1) remains open and unmerged. |

## Cloudflare Free CPU measurements

Measurements came from Cloudflare's `events.workersInvocations` account dataset filtered to `scriptName='taskpulse-api'`, the deployed script version, and `invocationType='cron'`. `cpuTimeUs` is runtime CPU in microseconds; `startupCpuTimeUs` is a separate metric and is **not included** in the Free 10 ms CPU limit measurement below. Post-deploy percentiles are computed with linear interpolation over the raw invocation values.

| Baseline window (UTC, 2026-11-11) | Cron samples | p50 | p95 | p99 | Maximum | Over 10 ms | Invocation errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| 19:05:53–22:15:53 | 189 | 6.122 ms | 11.168 ms | 15.167 ms | 16.322 ms | 21/189 | 0 |

Every over-budget baseline invocation was a Cron. Twenty of the 21 over-budget runs reported zero subrequests; one reported two. The production CPU profiler could not provide a function-level trace: attempts against the current version returned `The Worker has no loaded isolate in its recent execution locations`.

### Version #6 idle sample

| Window (UTC, 2026-11-11) | Cron samples | p50 | p95 | p99 | Maximum | Over 10 ms | Invocation errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| 22:28:53–22:47:53 | 20 | 4.590 ms | 7.237 ms | 7.497 ms | 7.562 ms | 0/20 | 0 |

This version reduced the idle Cron path to three D1 requests in the local D1-shaped harness (from six before the idle batching change). However, the first controlled workload with two overdue tasks and two team members consumed **17.606 ms** on version #6. Its events and notifications were still correct, but this is above the Free budget. That workload exposed additional overhead in per-event fanout and no-device outbox processing.

### Version #7 controlled workloads

Version `909da5a0-0b2c-4c21-91a3-2d89ac759f8a` batches bounded fanout member-page reads and writes across claimed events, then handles no-device and missing-notification outbox rows in the same D1 batch as delivery selection. Deadline uniqueness, lease handling, capped pages, and retries remain in place.

| Controlled production Cron case | CPU | Startup CPU (separate) | Subrequests | Status | D1 result |
|---|---:|---:|---:|---|---|
| Two overdue tasks, two team members, no registered devices | 7.253 ms | 6.341 ms | 0 | success | 2 unique deadline events; 2 fanout events; 4 team notifications; 4 `no_device` outbox rows |
| One reminder, two team members, no registered devices | 5.482 ms | 5.806 ms | 0 | success | 1 reminder event and 1 notification to the assignee; 1 `no_device` outbox row |

The overdue tasks crossed their deadline at 22:59:49.692 and were recorded by Cron at 22:59:54.257 (about 4.6 seconds later). Two subsequent Cron ticks left event, notification, and outbox counts unchanged. The reminder was recorded approximately 14.9 seconds after its configured reminder time. Both isolated fixtures were deleted by their exact IDs and follow-up queries returned zero remaining test rows.

Cloudflare's deployed CPU profiler could not capture a loaded isolate, so the exact JavaScript frame remains unknown. The measurements above establish that version #7's idle and no-device notification paths stayed below budget; they do not measure cryptographic signing or HTTP delivery for a valid FCM device token.

### Version #7 idle sample

| Window (UTC, 2026-11-11) | Idle Cron samples | p50 | p95 | p99 | Maximum | Over 10 ms | Invocation errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| 22:58:53–23:19:53 | 20 | 4.191 ms | 7.659 ms | 8.284 ms | 8.440 ms | 0/20 | 0 |

The sample includes version #7's ordinary idle ticks while excluding its two controlled work ticks (7.253 ms overdue/fanout and 5.482 ms reminder). All sampled Cron records were 60 seconds apart, returned success, and recorded zero subrequests. Cloudflare reports Worker startup CPU separately; it is not added to `cpuTimeUs` or the 10 ms per-invocation allowance. This closes the CPU check for idle, reminder, and no-device overdue/fanout paths. The device-backed FCM send path still has no valid token/device measurement.

## D1 and test results

| Check | Status | Evidence |
|---|---|---|
| Worker typecheck | PASS (local) | `npm run typecheck:worker` passed after the scheduler and D1 test-adapter changes. |
| Worker test suite | PASS (local) | `npm run typecheck:worker` and `npm run test:worker`: 4 test files, 17 tests passed. Includes JWT/auth, team isolation, task flow, idempotency, deadline races, fanout, retries, duplicate Cron, no-device outbox handling, backlog recovery, and idle/active D1 request bounds. |
| CI for current scheduler source | PASS | Run #35 ([workflow](https://github.com/fatoh112/taskaty/actions/runs/43119631321)) built commit `538266eeebe24a0b54b28a1f2774919838bf94aa`. Flutter analyze/tests, Worker typecheck/tests, `npm audit --audit-level=high`, connected debug APK build, and artifact upload all passed. |
| D1 quota usage | PASS (observed) | Cloudflare D1 Insights for 2026-11-11 UTC 00:00–23:10 reported 4,476 rows read, 1,151 written, and 1,956 queries. Size remained 266,240 bytes (0.090% of daily reads and 1.151% of daily writes). Counts include controlled fixture creation and cleanup. |
| Production overdue/reminder/fanout acceptance | PASS (controlled D1 fixture) | Cron processed two simultaneous overdue tasks, persisted four notifications to both test members, set four no-device outbox rows, and processed one assignee-only reminder. Two later ticks made no duplicates; exact test teams/users/tasks were removed and cleanup queries returned zero rows. |

Local SQL.js/FCM-mocked tests are not Cloudflare CPU measurements or physical push verification. Production Cron is currently detected by its `invocationType='cron'` analytics records and D1 heartbeat.

## Remaining release gates

| Requirement | Status | Limit |
|---|---|---|
| Team isolation | PASS (live and local) | A verified real account outside the isolated team's membership received `TEAM_NOT_FOUND` for task list/detail and could not mark that team's notification read. |
| Completion before deadline | PASS (local and previous live completion) | Production task completion persisted previously; this scheduler change is covered by the exact-deadline race test. |
| Overdue detection while app is closed | PASS (controlled live Cron) | Two test tasks became overdue without an Android app running; Cron detected and persisted their team-wide records. |
| Persistent overdue notification history | PASS (controlled live D1) | Four overdue notification records persisted for the two authorized test-team members; duplicate counts remained unchanged over later Cron ticks. |
| Real FCM delivery | UNVERIFIED | No valid device token or Android device. The invalid-token response is not delivery proof. |
| Arabic native voice and notification tap | UNVERIFIED on device | Parser/UI tests pass; device speech service and app tap routing were not physically exercised. |
| Connected APK | PASS (development build) | Run #35 artifact contains the configured Worker URL and Firebase app settings; it is not a production certification or public release. |
| Workers Free and Firebase Spark | PASS (owner confirmed) | No billing, plan upgrade, paid feature, or unrelated resource change occurred. |

The API and connected development APK are live. Version #7 passed the 20-tick idle sample plus controlled no-device overdue/fanout and reminder Cron checks below 10 ms. Actual device-backed FCM send CPU, physical push receipt, Android voice, and notification-tap behavior remain unverified. PR #1 remains open and unmerged. See [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md) for service limits and [DEPLOYMENT.md](DEPLOYMENT.md) for setup.
