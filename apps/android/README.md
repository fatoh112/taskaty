# Taskaty Flutter app

This app uses Firebase Authentication for accounts and the Cloudflare Worker for team and task data. It has no demo mode or local fake backend.

## Local Web development

From the repository root in PowerShell:

```powershell
.\scripts\run-web.ps1
```

The launcher retrieves the existing Firebase Web app's public SDK settings when needed, writes them under the ignored `.taskaty-local/` directory, generates the Firebase messaging service worker, and starts Flutter Web at `http://127.0.0.1:5173`. It targets Firebase project `taskaty-d3042` and the deployed Taskaty Worker. Add `127.0.0.1` to Firebase Authentication's authorized domains if it is not already listed.

Use `-Release` to run the same app in Release mode when Flutter Debug Chrome is unavailable. For config-only setup, use `-ConfigureOnly`. The optional `TASKATY_WEB_VAPID_KEY` environment variable supplies the Firebase Web Push public key. The current project has no VAPID key configured, so in-app notification history works but browser push is disabled.

All values passed to Flutter are public Firebase Web SDK configuration and the public Worker URL. `.taskaty-local/`, browser profiles, and test credentials must stay out of Git. Do not place a service-account key or other server secret in Flutter defines.

## Checks

Run from `apps/android`:

```powershell
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --dart-define-from-file=../../.taskaty-local/web-defines.json
```

The Flutter app also builds for Android; physical Android and FCM tests are tracked separately in the repository's `TEST_REPORT.md`.
