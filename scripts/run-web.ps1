param([switch]$Release, [switch]$ConfigureOnly)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'apps/android'
$local = Join-Path $root '.taskaty-local'
$sdkPath = Join-Path $local 'firebase-web-config.json'
$definesPath = Join-Path $local 'web-defines.json'
$workerPath = Join-Path $app 'web/firebase-messaging-sw.js'
$flutterFromPath = Get-Command flutter -ErrorAction SilentlyContinue
$flutterRootPath = if ($env:FLUTTER_ROOT) { Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat' } else { $null }
$flutter = if ($flutterRootPath -and (Test-Path $flutterRootPath)) { $flutterRootPath } elseif ($flutterFromPath) { $flutterFromPath.Source } else { 'E:\flutter\bin\flutter.bat' }
$webAppId = '1:476661033523:web:e42d31fd56ccfb69351146'

if (-not (Test-Path $flutter)) { throw "Flutter was not found at $flutter" }
New-Item -ItemType Directory -Force -Path $local | Out-Null
if (-not (Test-Path $sdkPath)) {
  $result = (& firebase apps:sdkconfig WEB $webAppId --project taskaty-d3042 --json 2>$null | Out-String | ConvertFrom-Json)
  if ($result.status -ne 'success') { throw 'Could not retrieve the existing Firebase Web app configuration.' }
  $result.result.sdkConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $sdkPath -Encoding utf8
}
$sdk = Get-Content -Raw $sdkPath | ConvertFrom-Json
if ($sdk.projectId -ne 'taskaty-d3042' -or $sdk.appId -ne $webAppId -or -not $sdk.authDomain -or -not $sdk.apiKey) {
  throw 'The cached Firebase Web app configuration does not match Taskaty.'
}
$vapid = $env:TASKATY_WEB_VAPID_KEY
$defines = [ordered]@{
  TASKPULSE_API_URL = 'https://taskpulse-api.sultan-food-internal.workers.dev'
  FIREBASE_API_KEY = $sdk.apiKey
  FIREBASE_APP_ID = $sdk.appId
  FIREBASE_PROJECT_ID = $sdk.projectId
  FIREBASE_SENDER_ID = $sdk.messagingSenderId
  FIREBASE_AUTH_DOMAIN = $sdk.authDomain
  FIREBASE_WEB_VAPID_KEY = if ($vapid) { $vapid } else { '' }
}
$defines | ConvertTo-Json | Set-Content -Path $definesPath -Encoding utf8
$workerConfig = [ordered]@{ apiKey = $sdk.apiKey; authDomain = $sdk.authDomain; projectId = $sdk.projectId; messagingSenderId = $sdk.messagingSenderId; appId = $sdk.appId } | ConvertTo-Json -Compress
@(
  'importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");'
  'importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");'
  "firebase.initializeApp($workerConfig);"
  'const messaging = firebase.messaging();'
) -join "`n" | Set-Content -Path $workerPath -Encoding utf8

if ($ConfigureOnly) { return }

Push-Location $app
try {
  $mode = if ($Release) { '--release' } else { '--debug' }
  & $flutter run -d chrome $mode --web-hostname 127.0.0.1 --web-port 5173 "--dart-define-from-file=$definesPath"
} finally { Pop-Location }
