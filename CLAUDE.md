# Fork notes

## Signing local builds
- On every machine, sign the build you install with that machine's own Apple Development certificate (the one Xcode creates). Don't install an ad-hoc build for daily use: macOS ties the Accessibility and Microphone grants and keychain access to the signature, and an ad-hoc signature changes with every rebuild, so the permissions are lost each time.
- `make local` picks the certificate automatically when exactly one "Apple Development" identity exists. With several, pass one: `make local LOCAL_CODESIGN_IDENTITY=<SHA-1>` (list them with `security find-identity -v -p codesigning`). Pass `LOCAL_CODESIGN_IDENTITY=-` only for a throwaway compile check.
- No certificate on a new machine: Xcode › Settings › Accounts › add the Apple ID › Manage Certificates › + › Apple Development. A free Apple ID is enough.
- The first time a machine switches from an ad-hoc build: quit VoiceInk, replace `/Applications/VoiceInk.app`, run `tccutil reset <service> com.prakashjoshipax.VoiceInk` for Accessibility, Microphone, ScreenCapture and AppleEvents, relaunch, grant the permissions once, and choose "Always Allow" on the keychain prompt. Later rebuilds keep the grants until the certificate is renewed (yearly).
- The certificate contains the owner's name and Apple ID email. Use it only for builds installed on the owner's own machines. CI builds and anything shared or published stay ad-hoc (`.github/workflows/build-ui-polish.yml`).

## Build timing
- `make local` deletes `.local-build` first, so every run is a full build. If the log stops at "Downloading package prebuilt … swift-syntax" for more than a few minutes, the download has hung (it once waited two hours): stop the build and run it again.
