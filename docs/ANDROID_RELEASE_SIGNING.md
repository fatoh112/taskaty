# Android release signing

The current repository has no persistent release keystore. The Android Gradle
release build therefore uses the generated debug key and is suitable for
installation/testing, but it is not a production release that can safely
receive signed app updates from a different build environment.

No release key has been generated. The owner must approve creating one before
that step because losing the key or its password prevents publishing updates
under the same Android signing identity.

## After owner approval

1. Generate a key on a trusted local machine with `keytool -genkeypair -v
   -keystore taskaty-release.jks -alias taskaty -keyalg RSA -keysize 4096
   -validity 10000`. Enter passwords interactively; do not put them in the
   command line or shell history.
2. Store the keystore and its passwords in separate secure backups. Do not add
   the keystore, its encoded form, passwords, or signing properties to Git.
3. Add the keystore and passwords as GitHub Actions repository **secrets**,
   never repository variables. The build workflow should write the keystore
   only into the runner's temporary directory, use it for signing, and remove
   it before artifact upload.
4. Keep the private keystore out of build artifacts. Record the public signer
   certificate fingerprint for future verification.

The debug-signed release-mode APK may be installed for evaluation, but it must
not be described as production-signed or used as the signing basis for a store
release.
