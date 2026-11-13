# Operations and free-tier limits

## Daily checks

- Inspect Cloudflare Workers daily request counts, invocation CPU, Cron events and D1 read/write/storage metrics.
- Inspect Firebase Authentication usage and the Firebase Cloud Messaging API quota/errors.
- Review Taskaty Settings → Backend diagnostics for API reachability and the last stored Cron heartbeat.
- Check notification outbox backlog and `worker_heartbeats.last_error_code` with the D1 dashboard/query UI if pushes or deadlines appear delayed.

## Capacity behavior

- Foreground clients refresh at 25-second intervals. Each active dashboard refresh uses task and dashboard endpoints. Request use scales with members and foreground time, so compare it to the account-wide 100,000 requests/day Free limit.
- Each Cron run inspects up to five overdue candidates and five reminder candidates, advances up to three fan-out events with pages of 30 members, and claims up to 15 notification recipients with up to two devices each. The measured harness ceiling was 47 combined D1/Google/FCM subrequests (46 observed in the ten-task test), under the Workers Free limit of 50. The configured 10 ms Cron CPU cap still requires real account telemetry.
- Under the checked-in load harness, ten overdue tasks for 30 members/two devices drained their 300 mocked deliveries in 21 simulated minute ticks (p50 deadline detection 1 minute; p95 2 minutes). A 100-task outage backlog persisted all 3,000 team notifications, with maximum due-to-detection latency 29 minutes; the 3,000 recipient records drained in 201 ticks with two devices per member and one transient retry. This is a local SQL.js/Node measurement, not a production timing guarantee.
- Free Cron CPU is 10 ms per invocation. Measure on the actual account before relying on push delivery; do not upgrade to address CPU/quota failures.
- D1 quota or network errors stay retryable. Pending outbox entries persist; delivery attempts are bounded and eventually dead-letter after the configured maximum.
- FCM delivery timing, device connectivity, Android power settings and force-stop can delay/drop the visible push. D1 history is the source of truth.

## Recovery

If an API returns a quota or temporary provider error, stop retry loops, inspect dashboard usage, and wait for the no-cost reset or reduce traffic. Pending work remains in D1. Never attach billing, use a trial credit, or upgrade a provider. Restore service only after confirming the account still uses the permanent Free/Spark plan.
