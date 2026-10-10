# Automatic updates

Producktive uses Sparkle 2.10.0 because it is a native macOS app. Sparkle manages
checking, downloading, signature verification, bundle replacement, and relaunch.
Defaults enable daily checks and automatic installation on quit. Settings bind
directly to Sparkle's persisted preferences; no extra scheduler is used.
The CLI remains independent of Sparkle and is replaced with the app bundle.
On launch, the app refreshes the CLI copy and managed skills for agents previously
installed through **Install agent skill**, keeping them in step with the app.
Unmanaged skills and agents never selected by the user are left untouched.

## Hosting

R2 stores the feed and archives. It is separate from the updater framework.
This follows DuckType's existing hosting at `https://updates.duck-type.com`,
using the `ducktype-app-updates` bucket and rclone's `r2` remote:

- Feed: `https://updates.duck-type.com/producktive/stable/appcast.xml`
- Archives: `producktive/stable/Producktive-VERSION-BUILD-universal.zip`
- One universal archive covers Apple silicon and Intel.

DuckType uses `tauri-plugin-updater` with Minisign-signed updater archives,
per-platform JSON manifests under `stable/` and `beta/`, and checks after startup
and every four hours. Producktive uses Sparkle's XML appcast and Ed25519 signing.
The two apps have separate signing keys and paths. No Tauri code is needed here.

## Signing keys

`scripts/release-config.sh` contains public configuration and the next release's
version/build. Increment `BUILD_NUMBER` for every update, including rebuilds;
Sparkle compares that number, not the marketing version.

The Producktive private update key is stored in the login Keychain under account
`producktive`. Only its public key is checked in. On the release Mac, inspect it:

```sh
swift package resolve
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account producktive -p
```

Back up the key securely using Sparkle's `generate_keys -x` option. On another
Mac import that backup with `generate_keys --account producktive -f PATH`.
Never generate a replacement key for an existing installation without planning
Sparkle's documented key rotation. For CI, use a protected file outside the
repository through `SPARKLE_PRIVATE_KEY_FILE`; do not put its contents on the
command line or in build logs.

## Build and publish

```sh
swift test
SIGNING_IDENTITY='Developer ID Application: DUCKTYPE LIMITED (DXY3Q8PYGP)' \
  NOTARY_PROFILE=YOUR_SAVED_PROFILE \
  RELEASE_NOTES_FILE=/absolute/path/release-notes.md \
  scripts/package-release.sh
scripts/publish-update.sh --dry-run
scripts/publish-update.sh
```

The package script embeds the framework with its symlinks intact, signs helpers
from the inside out with the app's identity, notarizes and staples the app, then
generates the signed feed from the final ZIP. `generate_appcast` checks that the
private signing key matches the public key embedded in the archive. Validation
rejects missing signatures, incorrect lengths, mismatched keys/versions/URLs,
and invalid signatures on the feed, archives, and external release notes.
Validation uses Apple's CryptoKit and the public key embedded in the app, without
accessing the private key.

Publishing requires notarization and Gatekeeper acceptance. It checks the live
feed to reject duplicate or older builds, uploads immutable archives and notes
first, checks that each payload is reachable at its public URL with identical
bytes, and advances the feed last. It also checks the published feed's bytes.
Keep `dist/updates` between releases so
Sparkle can retain older entries. The publisher uploads only referenced files
and never deletes old objects. R2 credentials stay in the rclone configuration.

Archives have `Cache-Control: public, max-age=31536000, immutable`; the feed has
`no-cache, max-age=0, must-revalidate`. Cloudflare Cache Rules must respect these
headers for `producktive/stable/appcast.xml` and must not override them with a
long edge TTL. If an existing rule cached that URL, purge it when first enabling
the feed. See [Cloudflare's R2/rclone documentation](https://developers.cloudflare.com/r2/examples/rclone/).

`RELEASE_VERSION`, `BUILD_NUMBER`, `UPDATE_BASE_URL`, `R2_UPDATE_REMOTE`,
`DIST_DIR`, and `SPARKLE_KEY_ACCOUNT` can be overridden in the environment.
`DIST_DIR` separates validation builds from the production release artifacts.
The public URL and
remote path must point to the same bucket namespace. Local ad hoc and CI builds
disable updating by default; `ENABLE_UPDATES=1` is available for integration
tests, and `ENABLE_UPDATES=0` explicitly disables it for any build.

## Validate an actual update

Use two Developer ID signed, notarized builds with the same key and feed and
increasing build numbers. Install the older build in Applications, publish the
newer build, and choose **Check for Updates…**. Check that the app relaunches,
reports the new version, retains its settings, and still reads the selected
deadline file. Also check automatic installation after quitting, disabled
automatic checks, offline manual checks, and a tampered archive being rejected.

Older Producktive releases have no updater. Users must install the first
Sparkle-enabled release manually once.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/),
and [update settings](https://sparkle-project.org/documentation/customization/).
