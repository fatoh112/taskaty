# Privacy notes

- Firebase Auth stores and verifies account credentials. The app does not request SMS authentication.
- Task titles, descriptions, memberships, activity, notification history and encrypted FCM tokens are stored in D1. API access uses the verified Firebase UID and active team membership.
- FCM registration tokens are hashed for lookup and AES-GCM encrypted at rest using `FCM_TOKEN_ENCRYPTION_KEY`. Service-account private-key JSON stays in a Worker Secret and is never sent to Android.
- Overdue pushes contain the assignee display name and task title to match the requested team alert. Android lock-screen privacy settings are controlled by the device owner. Notification records remain in D1 regardless of push delivery.
- Voice is opt-in and starts only after the microphone button. Android's installed speech recognition provider may send audio to its own service; network, offline behavior, retention and Egyptian Arabic support vary by device/provider. Taskaty submits only the user's editable, confirmed transcript, not raw audio.
- Offline edits are not queued. Once connectivity returns, foreground synchronization fetches the server state.

Review the selected Firebase and Android speech providers' privacy settings before production deployment.
