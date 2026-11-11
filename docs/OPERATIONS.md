# Operations and free-tier limits

## Daily checks

- Inspect Cloudflare Workers daily request counts, invocation CPU, Cron events and D1 read/write/storage metrics.
- Inspect Firebase Authentication usage and the Firebase Cloud Messaging API quota/errors.
- Review Taskaty Settings → Backend diagnostics for API reachability and the last stored Cron heartbeat.
- Check notification outbox backlog and `worker_heartbeats.last_error_code` with the D1 dashboard/query UI if pushes or deadlines appear delayed.

## Capacity behavior

- Foreground clients refresh at 25-second intervals. Each active dashboard refresh uses task and dashboard endpoints. Request use scales with members and foreground time, so compare it to the account-wide 100,000 requests/day Free limit.
- Each Cron run inspects at most one overdue candidate and one reminder candidate, advances at most one team-fanout page of ten members, and dispatches at most three recipients with up to two devices each. This intentionally bounds CPU/subrequests; backlog may take multiple minutes or longer to drain.
- Free Cron CPU is 10 ms per invocation. Measure on the actual account before relying on push delivery; do not upgrade to address CPU/quota failures.
- D1 quota or network errors stay retryable. Pending outbox entries persist; delivery attempts are bounded and eventually dead-letter after the configured maximum.
- FCM delivery timing, device connectivity, Android power settings and force-stop can delay/drop the visible push. D1 history is the source of truth.

## Recovery

If an API returns a quota or temporary provider error, stop retry loops, inspect dashboard usage, and wait for the no-cost reset or reduce traffic. Pending work remains in D1. Never attach billing, use a trial credit, or upgrade a provider. Restore service only after confirming the account still uses the permanent Free/Spark plan.
