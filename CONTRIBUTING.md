# Working on Plip

## Source map

| File | Responsibility |
| :--- | :--- |
| `Sources/Plip/PlistNode.swift` | Typed tree, decoding, validation, and snapshots |
| `Sources/Plip/App.swift` | App menus, NSDocument persistence, and native tree editor |
| `Sources/Plip/ItemEditor.swift` | Property editing sheet and local date/time control |
| `Sources/Plip/WelcomeController.swift` | Welcome screen and opening dropped file URLs |
| `Resources/Info.plist` | Bundle metadata and Finder document associations |
| `VERSION` | Single source of truth for app and installer versions |
| `Scripts/build.sh` | Native arm64 build, signing, PKG, ZIP, and checksums |
| `Scripts/test.sh` | Plist and document regression checks |
| `Scripts/verify-release.py` | Bundle, package, icon, and privacy verification |
| `.github/workflows/` | CI and release publishing |

## Development loop

```sh
bash Scripts/test.sh
bash Scripts/build.sh --pkg
python3 Scripts/verify-release.py
```

Also open the built app and check any changed UI. For edits to persistence, verify a saved file with `plutil` and reopen it. Use generated examples rather than personal or system preference files in tests and screenshots.

## Public repository privacy

Keep local caches, logs, credentials, signing files, crash reports, and private plist documents out of commits and release assets. Review staged changes with `git diff --cached` before pushing. The release check scans for personal filesystem paths, local hostnames, IP addresses, unexpected email addresses, and common credential formats. It supplements manual review; it cannot recognize every possible secret.

Maintainer commits use the public alias **Rodlip**, with `Rodlip@users.noreply.github.com` as their Git identity. Contributors should configure their own GitHub no-reply identity. The build maps source paths to relative paths and does not sign releases with personal certificates by default.

## Icon

The app icon is original native drawing code in `Scripts/make-icon.swift`. To change it, edit the drawing and run:

```sh
bash Scripts/generate-icon.sh
bash Scripts/build.sh --pkg
```

Commit both `Resources/PlipIcon.icns` and `docs/icon.png`. The generator includes every native and Retina size, up to 1024 pixels. Builds fail if the app icon is missing. The app explicitly loads its bundled icon at launch to avoid a stale generic Dock icon.

## Releases

1. Update `VERSION` to a new `major.minor.patch` value.
2. Update `docs/RELEASE-NOTES.md` for that release.
3. Run the tests, build, and release checks.
4. Commit and push to `main`.
5. Run the **Publish release** workflow, or push a matching `v<version>` tag.
6. Confirm the workflow succeeds and the GitHub Release contains the PKG, ZIP, and checksums.

The workflow uses GitHub's built-in repository token. No personal access token or Apple certificate is needed for the current ad-hoc signed releases. GitHub-hosted macOS runners and artifact behavior are documented in [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [artifact guide](https://docs.github.com/en/actions/tutorials/store-and-share-data).

## Optional Developer ID signing

For a local signed build, set `CODESIGN_IDENTITY` to a Developer ID Application identity and `INSTALLER_SIGN_IDENTITY` to a Developer ID Installer identity before running `Scripts/build.sh --pkg`. The build then enables hardened runtime and secure timestamps.

A public notarized release additionally needs Apple notarization and stapling. Do not commit certificates, passwords, private keys, or provisioning files. Developer ID certificates disclose their registered holder; do not enable them for a release intended to remain pseudonymous without reviewing that disclosure. The included GitHub workflows intentionally use ad-hoc signing.
