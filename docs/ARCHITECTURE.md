# Architecture

- `apps/android` is a Flutter Material 3 client with Riverpod providers, GoRouter navigation, Firebase email/password auth and native Android speech recognition.
- Firebase Authentication is the identity provider. The app sends Firebase ID tokens as bearer tokens; the Worker checks the RS256 signature and required Firebase claims against Google's rotating public keys.
- `backend/worker` is the authenticated REST API and one-minute Cron handler. `backend/migrations/0001_initial.sql` defines the only primary application database: Cloudflare D1.
- D1 owns team membership, task state, server-computed deadlines, activity, aggregate metrics, notification history, device registrations and durable notification work. Every API task/team read validates active membership.
- `notification_fanout` pages current team recipients; `notification_outbox` persists bounded FCM work and retry state. Unique event keys/constraints make logical deadline events idempotent. FCM delivery is best-effort and not exactly-once.
- The client conditionally polls active task/dashboard screens every 25 seconds while foregrounded and refreshes on resume or after mutations. D1 has no real-time listener. Local countdown ticks only affect presentation; the server deadline remains authoritative.

The architecture and limits are designed for Workers Free and Firebase Spark. See [the free-tier audit](../FREE_TIER_AUDIT.md) for capacity assumptions and [the test report](../TEST_REPORT.md) for what has actually been verified.
