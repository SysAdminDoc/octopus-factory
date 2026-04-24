---
name: Release Build Recipe
description: Build + sign + release pipeline per project type. Detects stack, runs appropriate build, signs artifacts, creates GitHub release with all platform artifacts attached. Cross-platform via GitHub Actions matrix. Covers Chrome/Firefox extensions, Python GUI/CLI, Android APK/AAB, C# WPF, C++, Rust, Go, Node.js. Enforces PyInstaller fork-bomb safeguards. Called by factory loop Q3; also usable standalone.
type: reference
originSessionId: 0bdf5c47-1a4d-4da7-953e-97bb4a97b38f
---
# Release Build Recipe

Takes a repo ready for release. Detects the project type, runs the right build + sign pipeline, creates a GitHub release, attaches signed artifacts for every platform the project targets.

## Trigger phrases
- **"ship a release for &lt;repo&gt;"**
- **"build and release &lt;repo&gt;"**
- **"cut v&lt;version&gt; for &lt;repo&gt;"**

## Called by factory loop Q3
The factory loop's Q3 step delegates to this recipe. Use standalone when you want release-only behavior without running the full factory pipeline.

## Directive

### Phase 0 — Version bump detection & release policy

Detect the intended version bump from (in order of precedence):

1. User's explicit directive ("cut v2.0.0")
2. Conventional-commit parsing of messages since last tag:
   - Any `BREAKING CHANGE:` trailer OR `feat!:` / `fix!:` / etc. → **major**
   - Any `feat:` without breaking marker → **minor**
   - `fix:` / `chore:` / `docs:` / `perf:` only → **patch**
3. CHANGELOG.md "Unreleased" section keywords:
   - "Breaking changes" / "Removed" headers → major
   - "Added" / "New feature" headers → minor
   - "Fixed" / "Changed" headers only → patch
4. Default: patch

**Release policy:**

| Bump type | Release? |
|---|---|
| Major | Always release |
| Minor | Always release |
| Patch | Release by default; skip with `--skip-patch-release` flag |

Patch-release-skipped still commits + pushes, just no GitHub Release.

### Phase 1 — Project type detection

Scan the repo for build manifests. A repo can match multiple types (e.g., browser extension + native host) — run each matching pipeline.

| Evidence | Detected type |
|---|---|
| `manifest.json` with `"manifest_version": 3` + chrome-only fields (`background.service_worker`, `action`) | **Chrome MV3 extension** |
| `manifest.json` with `browser_specific_settings.gecko` | **Firefox extension** (MV2 or MV3) |
| `*.user.js` with `==UserScript==` header | **Userscript** |
| `build.gradle(.kts)` + `android/` or `app/build.gradle` | **Android app** |
| `*.csproj` or `*.sln` with `<TargetFramework>net[0-9]`  | **C# / .NET** |
| `*.sln` + `*.vcxproj` | **C++ / Windows desktop** |
| `pyproject.toml` or `requirements.txt` + `*.spec` (PyInstaller) OR `entry_points` for GUI/CLI | **Python (buildable)** |
| `pyproject.toml` without entry points or spec | **Python library** (publish to PyPI instead) |
| `Cargo.toml` with `[[bin]]` | **Rust binary** |
| `go.mod` with `main.go` or `cmd/` | **Go binary** |
| `package.json` with `"bin"` entry | **Node.js CLI** |
| `package.json` with `"main"` only | **Node.js library** (publish to npm instead) |

Emit detection result to session log. If no type detected, halt with error — recipe doesn't guess.

### Phase 2 — Type-specific build pipeline

For each detected type, run the build. Cross-platform builds (Python, Rust, Go, C++) use GitHub Actions matrix — ensure `release.yml` has the matrix configured before triggering.

#### Chrome MV3 extension

**Build:**
```bash
# Pack as CRX3 using persistent private key
rtk npm run build    # or whatever the repo's build script is
# Pack the dist/ or unpacked/ directory
rtk node -e "
  const crxPack = require('crx-pack');
  const pem = require('fs').readFileSync('extension.pem');
  crxPack.pack({ path: 'dist/', privateKey: pem })
    .then(crx => require('fs').writeFileSync('<name>-v<ver>.crx', crx));
"
# Also produce ZIP for Chrome Web Store upload
cd dist/ && rtk zip -r ../<name>-v<ver>.zip . && cd ..
```

**Signing (CRX3):**
- Private key lives at `extension.pem` (root of repo) or `assets/extension.pem`.
- **NEVER regenerate** an existing `.pem` — users' installed extensions become orphaned if the key changes (new extension ID).
- If this is the first release and no `.pem` exists: generate `openssl genrsa -out extension.pem 2048`, add to `.gitignore`, store base64-encoded in GitHub Secret `EXTENSION_PEM`, record SHA-256 fingerprint in repo CLAUDE.md.
- The extension ID is derived deterministically from the pubkey.

**Artifacts attached to release:**
- `<name>-v<ver>.crx` (for direct user install: drag into chrome://extensions with developer mode)
- `<name>-v<ver>.zip` (for Chrome Web Store upload)

**User install instructions to put in release notes:**
```
1. Download <name>-v<ver>.crx
2. Open chrome://extensions, enable Developer mode (top right)
3. Drag the .crx file onto the page
```

#### Firefox extension

**Build:**
```bash
# Build (same as Chrome if shared codebase)
rtk npm run build:firefox
```

**Signing (via Mozilla AMO):**
```bash
rtk web-ext sign \
  --source-dir dist-firefox/ \
  --api-key="$AMO_JWT_ISSUER" \
  --api-secret="$AMO_JWT_SECRET" \
  --channel=unlisted \
  --artifacts-dir=web-ext-artifacts/
```

- `AMO_JWT_ISSUER` and `AMO_JWT_SECRET` stored as GitHub Secrets. Obtain from https://addons.mozilla.org/developers/addon/api/key/.
- `--channel=unlisted` = self-distributed (install from GitHub release).
- `--channel=listed` = submit to AMO for review + listing.
- **Unsigned XPIs do not run in Firefox release/beta.** Only Developer Edition / Nightly with `xpinstall.signatures.required=false` accept unsigned.

**Artifacts attached to release:**
- `<name>-v<ver>.xpi` (signed)

#### Userscript

**Build:** none (distributed as raw `.user.js`).

**Signing:** none (userscripts aren't signed; managers verify via @updateURL + @downloadURL integrity).

**Artifacts attached to release:**
- `<name>.user.js` (raw file; also linked as `@downloadURL` in userscript header)

Ensure `@version` in the userscript header matches the release tag. Factory's L5/Q3 doc-sync enforces this.

#### Android app

**Build:**
```bash
./gradlew clean
./gradlew assembleRelease     # APK
./gradlew bundleRelease       # AAB for Play Store
```

**Signing:**
- Keystore stored as base64 in GitHub Secret `KEYSTORE_BASE64`, decoded during workflow.
- `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` in Secrets.
- `app/build.gradle(.kts)` signing config:
  ```kotlin
  signingConfigs {
      create("release") {
          storeFile = file(System.getenv("KEYSTORE_PATH") ?: "release.keystore")
          storePassword = System.getenv("KEYSTORE_PASSWORD")
          keyAlias = System.getenv("KEY_ALIAS")
          keyPassword = System.getenv("KEY_PASSWORD")
      }
  }
  ```
- Use V2 + V3 signing schemes (required for Android 7+).
- **Same keystore for every release forever.** If the keystore is lost, users cannot upgrade — they must uninstall + reinstall.
- Record keystore SHA-256 fingerprint in repo CLAUDE.md so it's recoverable if the Secret is wiped.

**First-release keystore generation (if not already done):**
```bash
keytool -genkey -v \
  -keystore release.keystore \
  -keyalg RSA -keysize 4096 \
  -validity 25000 \
  -alias release \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=<project>, O=<user>, C=<country>"
# Base64 for GitHub Secret
base64 -w 0 release.keystore
```

**Artifacts attached to release:**
- `<name>-v<ver>-release.apk` (sideload/GitHub users)
- `<name>-v<ver>-release.aab` (Play Store upload)

**User install instructions:**
```
1. Download <name>-v<ver>-release.apk
2. Settings → Security → Install unknown apps → enable for your browser/file manager
3. Tap the APK to install
4. Upgrades work as long as the signing key hasn't changed
```

#### Python (buildable — GUI or CLI)

**PyInstaller fork-bomb safeguards (from ~/CLAUDE.md — NON-NEGOTIABLE):**

Before any PyInstaller build, verify these are present. **Refuse to ship if any are missing.**

1. **`multiprocessing.freeze_support()` is the first executable statement** in the entry script:
   ```python
   # app.py — top of file
   import multiprocessing
   multiprocessing.freeze_support()
   # ...rest of imports...
   ```

2. **Runtime hook is wired into the spec:**
   ```python
   # app.spec
   a = Analysis(
       ["app.py"],
       ...
       runtime_hooks=["assets/runtime_hook_mp.py"],
       ...
   )
   ```
   ```python
   # assets/runtime_hook_mp.py
   import multiprocessing
   multiprocessing.freeze_support()
   ```

3. **No unguarded `subprocess.run([sys.executable, ...])` calls.** Every call must be guarded by:
   ```python
   def _is_frozen() -> bool:
       return getattr(sys, "frozen", False) or hasattr(sys, "_MEIPASS")

   def _pip_install(spec: str) -> bool:
       if _is_frozen():
           return False
       # ...normal pip call...
   ```

4. **grep gate:** scan the codebase for `sys.executable` and `multiprocessing` — every usage must be reviewed against the rules above. Automated check:
   ```bash
   rtk grep -n 'subprocess.*sys\.executable' . || true
   rtk grep -n 'multiprocessing\.' . | head -20
   # Then manually verify _is_frozen() guards and freeze_support() placement
   ```

**Cross-platform build via GitHub Actions matrix:**

Generate or verify `.github/workflows/release.yml` has:

```yaml
name: Release
on:
  workflow_dispatch:
    inputs:
      version:
        required: true

permissions:
  contents: write

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { os: windows-latest, artifact-name: "<name>-v${{ inputs.version }}-win-x64.exe" }
          - { os: macos-latest,   artifact-name: "<name>-v${{ inputs.version }}-macos-arm64" }
          - { os: ubuntu-latest,  artifact-name: "<name>-v${{ inputs.version }}-linux-x64" }
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install -r requirements.txt pyinstaller
      - run: pyinstaller app.spec --clean --noconfirm
      - name: Rename artifact
        shell: bash
        run: |
          # Locate dist/ output, rename per matrix
          ...
      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.artifact-name }}
          path: dist/${{ matrix.artifact-name }}

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - run: |
          gh release create v${{ inputs.version }} \
            --title "v${{ inputs.version }}" \
            --notes-file CHANGELOG.md \
            */*
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Code signing (optional but recommended):**
- Windows: Authenticode signing with purchased code-signing cert. `signtool sign /fd SHA256 /f cert.pfx /p $CERT_PASSWORD artifact.exe`. Without this, Windows SmartScreen shows a warning.
- macOS: `codesign --deep --force --sign "Developer ID Application: <name>"`. Without this, Gatekeeper refuses to run. Notarization via `xcrun notarytool submit` unlocks distribution outside the App Store.
- Linux: no standard signing; distribute raw binary.

**Artifacts attached to release:**
- `<name>-v<ver>-win-x64.exe` (Windows)
- `<name>-v<ver>-macos-arm64` (Apple Silicon) + `<name>-v<ver>-macos-x64` (Intel) if supporting both
- `<name>-v<ver>-linux-x64` (Linux x86_64)

#### Python library (no entry point)

No binary build. Publish to PyPI:
```bash
rtk python -m build
rtk twine upload dist/*
```
`TWINE_USERNAME=__token__`, `TWINE_PASSWORD=<pypi-token>` in env or Secrets.

Also attach the wheel + sdist to the GitHub release as convenience.

#### C# / .NET

**Build:**
```bash
# Framework-dependent (smaller, requires .NET runtime)
rtk dotnet publish -c Release -r win-x64 --self-contained false

# Self-contained (~150 MB, no runtime dependency)
rtk dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

**Signing:** Authenticode as in Python section. Without it, SmartScreen warning.

**Artifacts:** single-file `.exe` per runtime, or a ZIP of the publish directory.

#### C++ / Windows desktop

**Build:**
```bash
# Via MSBuild (or vcpkg + cmake if cross-platform)
rtk msbuild <project>.sln /p:Configuration=Release /p:Platform=x64
```

**Signing:** Authenticode.

**Artifacts:** `.exe` plus any DLL dependencies (or static-linked). Optionally bundle via NSIS installer.

#### Rust

**Build:**
```bash
# Cross-platform via GitHub Actions matrix
rtk cargo build --release --target x86_64-pc-windows-msvc   # Windows
rtk cargo build --release --target x86_64-apple-darwin      # macOS Intel
rtk cargo build --release --target aarch64-apple-darwin     # macOS Apple Silicon
rtk cargo build --release --target x86_64-unknown-linux-gnu # Linux
```

**Signing:** Authenticode / codesign as applicable.

**Artifacts:** one binary per target, named per platform convention.

#### Go

**Build** (cross-compiles natively, no matrix needed):
```bash
for GOOS in windows darwin linux; do
  for GOARCH in amd64 arm64; do
    [[ "$GOOS" == "windows" && "$GOARCH" == "arm64" ]] && continue
    output="<name>-v<ver>-${GOOS}-${GOARCH}"
    [[ "$GOOS" == "windows" ]] && output+=".exe"
    GOOS=$GOOS GOARCH=$GOARCH rtk go build -o "dist/$output" -ldflags "-s -w"
  done
done
```

**Signing:** optional Authenticode / codesign.

**Artifacts:** 5 binaries (windows-amd64, darwin-amd64, darwin-arm64, linux-amd64, linux-arm64).

#### Node.js CLI

**Build:** compile to single-file binaries via `pkg` or `nexe`:
```bash
rtk pkg . --targets node20-win-x64,node20-macos-arm64,node20-linux-x64 --out-path dist/
```

**Signing:** Authenticode / codesign.

**Artifacts:** one binary per target.

### Phase 3 — Pre-release verification (gates the release)

Before creating the GitHub release, verify every artifact:

1. **Artifact exists** at the expected path with expected name.
2. **Artifact is signed** (where signing applies): `signtool verify` / `codesign -v` / `apksigner verify` / `web-ext lint`.
3. **Artifact runs** (smoke test — executes the artifact and verifies a basic output):
   - Executables: `<artifact> --version` returns expected string.
   - Extensions: load unpacked build into a headless browser via Playwright, verify the extension loads without errors.
   - APK: `aapt dump badging <apk>` shows the expected package name + versionName.
4. **Artifact integrity:** generate SHA-256 checksums for all artifacts, write to `SHA256SUMS.txt` (attach to release).

Any failed verification halts release creation. No partial releases.

### Phase 4 — GitHub Release creation

```bash
# Create draft release with body from CHANGELOG "Unreleased" (now "vX.Y.Z — date")
rtk gh release create "v<version>" \
  --draft \
  --title "v<version>" \
  --notes-file release-notes-<version>.md \
  <all-artifacts> \
  SHA256SUMS.txt
```

Draft first, then promote to full release after final review (done by agent, not user, unless user opts for manual).

**Release notes structure** (generated from CHANGELOG):
```markdown
## What's new in v<version>

<summary of changes from CHANGELOG>

## Install

<install instructions from the project type's section above>

## Checksums

SHA-256 checksums attached as SHA256SUMS.txt.

## Signing

<per-type signing info: extension ID / APK fingerprint / code-sign cert thumbprint>
```

### Phase 5 — Post-release verification

1. `rtk gh release view v<version>` — confirm all artifacts uploaded.
2. Download one artifact from the release page + smoke-test it (different from pre-release test; this catches upload corruption).
3. Confirm GitHub serves the release page via `rtk curl` with cache-bust.
4. Update repo CLAUDE.md version history + project memory file.
5. Announce release in continuation brief.

### Phase 6 — Rollback (on any Phase 3/4/5 failure)

```bash
rtk gh release delete v<version> --yes       # if created
rtk git push origin :refs/tags/v<version>    # delete remote tag
rtk git tag -d v<version>                    # delete local tag
rtk git revert --no-edit <release-commit>    # undo version bump
rtk git push
```

Halt + surface error. Do not retry automatically.

## Non-Negotiable Rules

- **PyInstaller fork-bomb rules** are mandatory for every Python executable build. Refuse to ship if not satisfied.
- **Keystores and signing keys never regenerate** unless this is literally the first release. Records fingerprints in CLAUDE.md so loss is recoverable.
- **Unsigned extensions don't ship** on Chrome/Firefox release channels. If signing credentials missing, halt — don't ship unsigned and hope.
- **SHA256SUMS.txt** attached to every release so users can verify integrity.
- **Draft-first, promote after verification** — never create a full release that hasn't passed Phase 5 verification.
- **Rollback on any failure** per Phase 6 — no zombie releases.
- **Version strings match everywhere** before any build (manifest, package.json, @version in userscripts, README badge, CHANGELOG header, project memory file).
- **Cross-platform builds run in GitHub Actions matrix**, not on the host machine. Local PyInstaller builds only target the host OS.

## Credentials required (store as GitHub Secrets)

| Secret name | When needed |
|---|---|
| `EXTENSION_PEM` | Chrome extension signing (base64-encoded .pem) |
| `AMO_JWT_ISSUER` + `AMO_JWT_SECRET` | Firefox extension signing |
| `KEYSTORE_BASE64` + `KEYSTORE_PASSWORD` + `KEY_ALIAS` + `KEY_PASSWORD` | Android APK signing |
| `WINDOWS_CERT_PFX` + `WINDOWS_CERT_PASSWORD` | Authenticode signing (optional) |
| `APPLE_DEVELOPER_ID` + `APPLE_CERT_P12` + `APPLE_CERT_PASSWORD` | macOS codesign + notarization (optional) |
| `TWINE_PASSWORD` | PyPI publishing (Python libraries only) |

Record which secrets each repo needs in its CLAUDE.md "Build Environment" section.

## Supply-chain attestation (inherits from factory Q3)

For every release, regardless of project type:
- **SBOM:** `syft <repo> -o spdx-json=SBOM.spdx.json` — attached to release
- **Provenance:** `slsa-framework/slsa-github-generator` emits signed provenance from release.yml
- **Artifact signing:** `cosign sign-blob --yes --key env://COSIGN_KEY <artifact>` or keyless via OIDC if public repo
- **Verification gate:** `cosign verify-blob` must pass before release promoted from draft

Required for EU CRA (Sept 2026) and EU AI Act (Aug 2026) compliance.
