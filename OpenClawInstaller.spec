# PyInstaller spec: 跨平台兼容版本（Windows / macOS / Linux）
#
# 用法：
#   pip install pyinstaller
#   pyinstaller OpenClawInstaller.spec

import sys
from PyInstaller.utils.hooks import collect_submodules

block_cipher = None

hiddenimports = collect_submodules("requests")

a = Analysis(
    ["app/main.py"],
    pathex=["."],
    binaries=[],
    datas=[
        ("assets/OpenClaw-Skill-Project/scripts/install.ps1", "assets/OpenClaw-Skill-Project/scripts"),
        ("assets/OpenClaw-Skill-Project/scripts/uninstall.ps1", "assets/OpenClaw-Skill-Project/scripts"),
        ("assets/OpenClaw-Skill-Project/scripts/install.sh", "assets/OpenClaw-Skill-Project/scripts"),
        ("assets/OpenClaw-Skill-Project/scripts/uninstall.sh", "assets/OpenClaw-Skill-Project/scripts"),
    ],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# Windows: 使用图标
icon_path = "assets/app_icon.ico" if sys.platform.startswith("win") else None

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="OpenClawInstaller",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon_path,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    a.zipfiles,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="OpenClawInstaller",
)
