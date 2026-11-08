# Fork CI: automatic `ui-polish` builds

This fork (`eric1932/VoiceInk`) builds the `ui-polish` branch on GitHub Actions and publishes a signed
`VoiceInk.app` as an artifact. These files exist only in this fork:

| File | What it does |
| --- | --- |
| `.github/workflows/build-ui-polish.yml` | Runs on every push to `ui-polish`. Builds, signs and uploads the artifact `VoiceInk-ui-polish`. |
| `.github/actions/build-voiceink/action.yml` | The build itself, the same as `make local`: whisper.xcframework in `~/VoiceInk-Dependencies` (cached by whisper.cpp commit), then `make local` with the certificate from the secrets. |
| `.github/workflows/sync-upstream.yml` | Optional and not scheduled yet. Rebases `ui-polish` onto `Beingpax/VoiceInk` `main`, builds it, and force-pushes only if the build passes. On a conflict it pushes nothing and opens an issue. |

Runner: `macos-26` (Xcode 26.6, macOS 26.5 SDK, which `glassEffect` needs). A manual run can pick the
`xcode-27` preview image instead. The first build, or a new whisper.cpp commit, also builds the
xcframework for every platform, which takes longer. After that the framework comes from the cache.

## Secrets

Add these under **Settings → Secrets and variables → Actions** (or with `gh secret set`, below):

| Secret | Required | Value |
| --- | --- | --- |
| `APPLE_DEV_CERT_P12_BASE64` | for signed builds | base64 of your exported Apple Development `.p12` (certificate **and** private key) |
| `APPLE_DEV_CERT_PASSWORD` | for signed builds | the password you set when exporting the `.p12` |
| `UPSTREAM_SYNC_TOKEN` | only if the sync job's push is refused | fine-grained token for this repo only, with **Contents: Read and write** and **Workflows: Read and write** |

Without the certificate secrets the build still runs, but it is ad-hoc signed and shows a warning.
macOS then treats every install as a new app, so Accessibility, Microphone and Keychain access have to
be granted again.

### Export the certificate (on your Mac)

Use the same certificate `make local` uses: **Apple Development** from your Personal Team
(`2P5BKVUKAH`). Builds signed with it keep the permissions your local builds already have, because
macOS identifies the app by bundle ID plus certificate name. Don't create a new certificate for CI.

1. Open **Keychain Access** → **login** keychain → **My Certificates**.
2. Find **Apple Development: <your Apple ID> (…)**. Expand it and check that a private key is underneath.
3. Right-click the certificate → **Export "Apple Development: …"** → format **Personal Information
   Exchange (.p12)** → save as `~/Desktop/voiceink-signing.p12` and choose a strong password.
   (Alternative: Xcode → Settings → Accounts → your team → Manage Certificates → right-click → Export.)
4. Store both secrets. Each `gh secret set` reads the value from stdin or prompts for it, so it never
   ends up in your shell history:

   ```bash
   base64 -i ~/Desktop/voiceink-signing.p12 | gh secret set APPLE_DEV_CERT_P12_BASE64 -R eric1932/VoiceInk
   ```

   ```bash
   gh secret set APPLE_DEV_CERT_PASSWORD -R eric1932/VoiceInk
   ```

5. Delete the exported file:

   ```bash
   rm ~/Desktop/voiceink-signing.p12
   ```

The certificate expires on 2027-11-08. When you renew it, export the new one and repeat steps 3–5.
After a renewal, macOS will ask for permissions once more.

The runner imports the `.p12` into a temporary keychain that is deleted at the end of the job. It masks
the certificate name (your Apple ID email) in the logs. Note that artifacts of a public repository can
be downloaded by any signed-in GitHub user, and the app's signature contains that certificate name.

## Install a CI build

Every successful run uploads the artifact `VoiceInk-ui-polish`. It contains `VoiceInk-<version>-<commit>.zip`
(made with `ditto`, so the bundle and its signature stay intact) and `BUILD-INFO.txt`. Fetch the newest
one, then replace the installed app:

```bash
rm -rf /tmp/voiceink-ci && gh run download -R eric1932/VoiceInk -n VoiceInk-ui-polish -D /tmp/voiceink-ci && cat /tmp/voiceink-ci/BUILD-INFO.txt
```

```bash
osascript -e 'tell application id "com.prakashjoshipax.VoiceInk" to quit'; rm -rf /Applications/VoiceInk.app && ditto -x -k /tmp/voiceink-ci/VoiceInk-*.zip /Applications && xattr -cr /Applications/VoiceInk.app && open /Applications/VoiceInk.app
```

If you download the artifact in a browser instead, unzip it twice (artifact zip, then the app zip) and
run `xattr -cr` on the app. The build isn't notarized, so Gatekeeper would otherwise block the
quarantined copy.

## Keeping `ui-polish` current with upstream

By hand: rebase locally and push. The push triggers a build.

```bash
git fetch upstream && git switch ui-polish && git rebase upstream/main && git push --force-with-lease origin ui-polish
```

Automatically, with `sync-upstream.yml`:

1. Scheduled and manual workflows only run from the repository's **default branch**. Make `ui-polish`
   the fork's default branch (Settings → General → Default branch) so `main` stays a clean mirror of
   upstream.
2. Enable **Issues** on the fork (Settings → General → Features). The job reports conflicts there.
3. Uncomment the `schedule:` block in `sync-upstream.yml`, or run it from the Actions tab.
4. If the push is refused with "refusing to allow a GitHub App to create or update workflow", add the
   `UPSTREAM_SYNC_TOKEN` secret. Pushes made with that token also trigger `build-ui-polish.yml`, which
   means a second build of the same commit.

After the job has pushed, run `git pull --rebase` on your Mac before you push local work to `ui-polish`.

## Knobs

- **whisper.cpp version**: `whisper-cpp-ref` in `.github/actions/build-voiceink/action.yml` is pinned to
  the commit that was built locally. Bump it to update; the new commit builds once, then comes from the cache.
- **Xcode**: run **Build ui-polish** manually with `runner: xcode-27` (and optionally `xcode-version: 27.2`).
