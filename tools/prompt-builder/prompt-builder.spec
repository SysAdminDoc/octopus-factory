# PyInstaller spec for the prompt builder.
#
# Build:
#   cd tools/prompt-builder
#   python -m PyInstaller prompt-builder.spec --clean
#
# Output:
#   dist/prompt-builder.exe       (Windows)
#   dist/prompt-builder           (Linux / macOS)
#
# Fork-bomb safeguards (per ~/.claude/CLAUDE.md):
#   - prompt_builder/__main__.py calls multiprocessing.freeze_support() first.
#   - runtime_hook_mp.py mirrors the call so workers can't escape via direct module imports.
#   - The build does NOT package any subprocess that re-invokes sys.executable.
# pylint: disable=undefined-variable

block_cipher = None

a = Analysis(
    ["prompt_builder/__main__.py"],
    pathex=["."],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=["runtime_hook_mp.py"],
    excludes=[
        # Trim the binary — these aren't used and bulk it up significantly.
        "tkinter",
        "test",
        "unittest",
        "pydoc",
        "pdb",
        "doctest",
        "pip",
        "setuptools",
        "wheel",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="prompt-builder",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,         # GUI app — no terminal window on Windows
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
