---
name: Logo & Icon Generation Directive
description: Produces a clean project logo and complete icon set using the cheapest viable path (SVG-via-Copilot → ImageMagick rasterization is primary). Referenced by factory G-phase (existing projects that need a logo) and release-build recipe P5 (new projects). Never requires OpenAI billing for simple icon work.
type: knowledge
triggers: [logo, icon, branding, favicon, app icon, svg, ico]
agents: [implementer]
---

# Logo & Icon Generation Directive

Referenced by factory G-phase and release-build recipe P5. Produces a complete, reusable icon set for any project type. SVG-first by default — rasterization pipelines only when the project needs photorealistic imagery.

## Three generation paths (in priority order)

| Path | Best for | Cost | API key needed |
|---|---|---|---|
| **1. SVG-via-Copilot** | App icons, favicons, monochrome logos, geometric marks | ~$0.01 | None — Copilot subscription |
| **2. Codex gpt-image-1** | Photorealistic imagery, complex compositions, branded marketing assets | ~$0.04/image | `OPENAI_API_KEY` |
| **3. Gemini image** | Fallback when 1 and 2 unavailable | Gemini tier | `GEMINI_API_KEY` |

The G-phase picks Path 1 by default because most project icons are geometric, not photorealistic. Falls through to Path 2 on explicit `--raster-logo` flag or when the icon brief explicitly calls for photographic content. Path 3 is last resort.

## Path 1 — SVG-via-Copilot (primary)

### Why SVG first

Project icons (app icons, favicons, file-browser marks) are almost always geometric. LLMs write clean SVG better than they generate 1024×1024 pixel art. SVG is lossless, scales to every size the project needs, and rasterizes deterministically.

### Generation

```bash
# Step 1: Copilot generates the SVG source
PROMPT="Design a minimal professional app icon for <PROJECT>.
Description: <ONE-LINE DESCRIPTION>
Style: <geometric / flat / glyph / emblem — pick one>
Palette: <from repo CLAUDE.md branding, or a minimal 2-color palette>
Constraints:
- viewBox=\"0 0 512 512\"
- Single clean geometric shape (no gradients, no complex paths)
- Works at 16×16 to 512×512
- High contrast for small sizes
- Transparent background
Output: raw SVG only, no wrapper markdown or explanation."

echo "$PROMPT" | copilot --no-ask-user --model claude-sonnet-4.6 > assets/icons/icon.svg
# OR: copilot --no-ask-user --model gpt-5.4 (whichever your preset routes to)
```

Validate the output parses as SVG before committing:
```bash
xmllint --noout assets/icons/icon.svg || { echo "invalid SVG, retry"; exit 1; }
```

### Rasterization to required sizes

```bash
mkdir -p assets/icons/

# Rasterize to standard PNG sizes via ImageMagick
for size in 16 32 48 64 128 256 512 1024; do
    magick -background none -size ${size}x${size} \
        assets/icons/icon.svg \
        assets/icons/icon-${size}.png
done

# Build multi-resolution .ico (Windows)
magick assets/icons/icon-16.png \
       assets/icons/icon-32.png \
       assets/icons/icon-48.png \
       assets/icons/icon-256.png \
       assets/icons/icon.ico

# Build .icns (macOS) — optional, requires iconutil on macOS
if command -v iconutil &>/dev/null; then
    mkdir -p /tmp/icon.iconset
    cp assets/icons/icon-16.png    /tmp/icon.iconset/icon_16x16.png
    cp assets/icons/icon-32.png    /tmp/icon.iconset/icon_16x16@2x.png
    cp assets/icons/icon-32.png    /tmp/icon.iconset/icon_32x32.png
    cp assets/icons/icon-64.png    /tmp/icon.iconset/icon_32x32@2x.png
    cp assets/icons/icon-128.png   /tmp/icon.iconset/icon_128x128.png
    cp assets/icons/icon-256.png   /tmp/icon.iconset/icon_128x128@2x.png
    cp assets/icons/icon-256.png   /tmp/icon.iconset/icon_256x256.png
    cp assets/icons/icon-512.png   /tmp/icon.iconset/icon_256x256@2x.png
    cp assets/icons/icon-512.png   /tmp/icon.iconset/icon_512x512.png
    cp assets/icons/icon-1024.png  /tmp/icon.iconset/icon_512x512@2x.png
    iconutil -c icns /tmp/icon.iconset -o assets/icons/icon.icns
    rm -rf /tmp/icon.iconset
fi

# Favicon for web projects
cp assets/icons/icon-32.png assets/icons/favicon-32.png
cp assets/icons/icon-16.png assets/icons/favicon-16.png
```

### Dependencies

ImageMagick (`magick` command) — install via:
- macOS: `brew install imagemagick`
- Linux: `apt install imagemagick` / `dnf install ImageMagick`
- Windows: `scoop install imagemagick` / `winget install ImageMagick.ImageMagick`
- Docker fallback: `docker run --rm -v $PWD:/w -w /w dpokidov/imagemagick magick ...`

Halt G-phase if ImageMagick missing and user hasn't opted into manual icon drop.

## Path 2 — Codex gpt-image-1 (raster-first)

For photorealistic / complex imagery only. Requires `OPENAI_API_KEY` in env or `~/.codex/auth.json`.

```bash
curl -s https://api.openai.com/v1/images/generations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-image-1",
    "prompt": "<brief from repo CLAUDE.md branding section>",
    "size": "1024x1024",
    "background": "transparent",
    "n": 1
  }' | jq -r '.data[0].b64_json' | base64 -d > assets/icons/icon-1024.png

# Downsize to other standard sizes
for size in 16 32 48 64 128 256 512; do
    magick assets/icons/icon-1024.png -resize ${size}x${size} \
        assets/icons/icon-${size}.png
done
# Then build .ico / .icns as in Path 1
```

If the API returns `billing_hard_limit_reached` or `insufficient_quota`, **do not retry** — surface the error, log to session, fall through to Path 3.

## Path 3 — Gemini image (fallback)

```bash
gemini -m gemini-3-pro-image-preview \
  -p "Design a minimal professional app icon for <PROJECT>.
      Transparent background. 1024×1024 PNG." \
  --approval-mode yolo \
  -o image > assets/icons/icon-1024.png
```

Requires `GEMINI_API_KEY` (OAuth-tier Gemini CLI only exposes text models). If unavailable, halt G-phase and write a logo brief to `assets/logo-prompt.md` for the user to generate manually.

## Wiring after generation

Regardless of path, wire the produced assets into the project. Detect stack from build files:

### WPF / .NET (Images is this)

```xml
<!-- <project>.csproj -->
<PropertyGroup>
  <ApplicationIcon>assets\icons\icon.ico</ApplicationIcon>
</PropertyGroup>
<ItemGroup>
  <Resource Include="assets\icons\icon.ico" />
</ItemGroup>
```

### Chrome MV3 extension

```json
{
  "icons": {
    "16": "assets/icons/icon-16.png",
    "32": "assets/icons/icon-32.png",
    "48": "assets/icons/icon-48.png",
    "128": "assets/icons/icon-128.png"
  },
  "action": {
    "default_icon": {
      "16": "assets/icons/icon-16.png",
      "32": "assets/icons/icon-32.png"
    }
  }
}
```

### Android

Generate adaptive icons via Android Studio's Asset Studio format — foreground (monochrome SVG content) + background (solid color). Place at:
```
app/src/main/res/mipmap-*/ic_launcher.png
app/src/main/res/mipmap-*/ic_launcher_round.png
app/src/main/res/drawable/ic_launcher_foreground.xml
```

### Web app / PWA

```html
<link rel="icon" type="image/svg+xml" href="/assets/icons/icon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="/assets/icons/favicon-32.png">
<link rel="icon" type="image/png" sizes="16x16" href="/assets/icons/favicon-16.png">
<link rel="apple-touch-icon" sizes="180x180" href="/assets/icons/icon-256.png">
```

Manifest:
```json
{
  "icons": [
    { "src": "/assets/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/assets/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### README header

```markdown
<p align="center">
  <img src="assets/icons/icon-128.png" alt="<PROJECT> icon" width="128" height="128">
</p>

<h1 align="center"><PROJECT></h1>
```

### Update repo CLAUDE.md "Module map"

Record the icon set's canonical location so future factory runs don't regenerate it:
```
## Assets
- `assets/icons/icon.svg` — master SVG source
- `assets/icons/icon-{16,32,48,64,128,256,512,1024}.png` — rasterized sizes
- `assets/icons/icon.ico` — Windows multi-res icon
- `assets/icons/icon.icns` — macOS icon bundle (if present)
```

## Non-Negotiable Rules

- **Never overwrite an existing signed icon** (e.g., Chrome extension with established extension ID — replacing the icon changes user-facing identity but not the ID; replacing the `.pem` orphans users). Safe to replace `.png` and `.ico` if the `.pem` / keystore stays intact.
- **Transparent backgrounds mandatory** for PNG icons unless the project explicitly specifies otherwise.
- **Record the source path** (SVG master or raster master) in repo CLAUDE.md so future regenerations aren't blind.
- **Validate before committing** — SVG must parse, PNGs must be readable by ImageMagick `identify`, .ico must contain at least one size.
- **Per-size commit not required** — one atomic commit with all sizes is fine: `assets: add icon set (SVG + rasterized PNGs + .ico)`.
- **Secret scan + sacred-cow gates apply** (per directive-secret-scan.md + circuit-breakers).

## Gate

G-phase (the factory-loop phase that invokes this directive) auto-skips if:

- Repo already has `assets/icons/icon.svg` AND all required raster sizes present AND not flagged in CLAUDE.md "Module map" as stale
- User passed `--skip-logo`
- Repo is explicitly brand-less (CLAUDE.md says so)

Otherwise G-phase runs on existing projects where icons are missing. For NEW projects, the recipe's P5 preflight step runs instead (same directive, same paths).
