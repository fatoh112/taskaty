# Taskaty verification report

**Updated:** 2026-11-12 (Africa/Cairo)
**Scope:** Connected development APK, Cloudflare Free CPU reduction, live Cron, D1 usage, and notification acceptance. No service was upgraded and no billing was activated.

## Deployment and account state

| Check | Status | Evidence |
|---|---|---|
| Cloudflare plan | PASS (owner confirmation) | Owner confirmed account `f4c2197713164b02bd5fc0ba861da81d` is Workers Free ($0). `cf auth whoami` reported authenticated and token valid for that account. |
| Firebase plan | PASS (owner confirmation) | Owner confirmed Firebase project `taskaty-d3042` is Spark. No Blaze or Cloud Billing was enabled. |
| D1 database and migration | PASS | Dedicated `taskaty-db` (`6ef4b4e0-915d-493f-8a4e-2d320aca296c`) contains the checked-in migration. No unrelated database was changed. |
| Worker version and Cron | DEPLOYED | `taskpulse-api` is live at [https://taskpulse-api.sultan-food-internal.workers.dev](https://taskpulse-api.sultan-food-internal.workers.dev), current version `909da5a0-0b2c-4c21-91a3-2d89ac759f8a`, D1 binding retained, and Cron remains `* * * * *`. `cf workers versions get` confirmed both FCM secret bindings and the Firebase project variable remain configured. |
| Production health | PASS | `/health` returned 200 with `status: ok`, recent scheduler start/finish timestamps, and no scheduler error. |
| Existing live account/API smoke | PASS (previous run) | Two temporary Firebase email/password accounts registered and signed in; after satisfying the Worker email-verification gate, they created/joined a team, viewed an assigned task, and persisted completion. Temporary users and data were removed. This did not verify the user-facing email link flow. |
| Assignment notification history | PASS (previous run) | The assigned task appeared for both authenticated team users and the assignment notification was returned through authenticated history and found in D1. |
| FCM server authentication | PASS (previous run); delivery UNVERIFIED | Worker credentials are secrets only. An intentionally invalid token reached FCM HTTP v1 and returned HTTP 400, confirming OAuth/server connectivity but not delivery. No valid device token or physical push receipt is available. |
| Connected debug APK | PASS (development artifact) | CI run [#33](https://github.com/fatoh112/taskaty/actions/runs/43108158419) succeeded, including the debug APK build. [Artifact 13895247109](https://github.com/fatoh112/taskaty/actions/runs/43108158419/artifacts/13895247109), named `taskaty-debug-apk-33`, contains the public Firebase settings and deployed `TASKPULSE_API_URL`; expires 2026-11-14 22:07:57 UTC. **DEVELOPMENT TEST ONLY**; no public release. This build predates the Worker-only scheduler optimization. |
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
| CI for current scheduler source | PENDING | Run #33 built the connected APK before the #7 scheduler changes. Push the verified source/docs and wait for a new Android workflow before calling this revision CI-verified. |
| D1 quota usage | PASS (observed) | Cloudflare D1 Insights for 2026-11-11 UTC 00:00–23:10 reported 4,476 rows read, 1,151 written, and 1,956 queries. Size remained 266,240 bytes (0.090% of daily reads and 1.151% of daily writes). Counts include controlled fixture creation and cleanup. |
| Production overdue/reminder/fanout acceptance | PASS (controlled D1 fixture) | Cron processed two simultaneous overdue tasks, persisted four notifications to both test members, set four no-device outbox rows, and processed one assignee-only reminder. Two later ticks made no duplicates; exact test teams/users/tasks were removed and cleanup queries returned zero rows. |

Local SQL.js/FCM-mocked tests are not Cloudflare CPU measurements or physical push verification. Production Cron is currently detected by its `invocationType='cron'` analytics records and D1 heartbeat.

## Remaining release gates

| Requirement | Status | Limit |
|---|---|---|
| Team isolation | PASS (local); UNVERIFIED live outsider test | Local authorization tests pass; no new live outsider account was used in this scheduler milestone. |
| Completion before deadline | PASS (local and previous live completion) | Production task completion persisted previously; this scheduler change is covered by the exact-deadline race test. |
| Overdue detection while app is closed | PASS (controlled live Cron) | Two test tasks became overdue without an Android app running; Cron detected and persisted their team-wide records. |
| Persistent overdue notification history | PASS (controlled live D1) | Four overdue notification records persisted for the two authorized test-team members; duplicate counts remained unchanged over later Cron ticks. |
| Real FCM delivery | UNVERIFIED | No valid device token or Android device. The invalid-token response is not delivery proof. |
| Arabic native voice and notification tap | UNVERIFIED on device | Parser/UI tests pass; device speech service and app tap routing were not physically exercised. |
| Connected APK | PASS (development build) | Run #33 APK has the actual Worker URL and Firebase app settings; it is not a production certification or public release. |
| Workers Free and Firebase Spark | PASS (owner confirmed) | No billing, plan upgrade, paid feature, or unrelated resource change occurred. |

The API and connected development APK are live. Version #7 passed the 20-tick idle sample plus controlled no-device overdue/fanout and reminder Cron checks below 10 ms. Actual device-backed FCM send CPU, physical push receipt, Android voice, and notification-tap behavior remain unverified. A new CI APK for this Worker revision is pending. See [FREE_TIER_AUDIT.md](FREE_TIER_AUDIT.md) for service limits and [DEPLOYMENT.md](DEPLOYMENT.md) for setup.
