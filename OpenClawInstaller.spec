# PyInstaller spec：把 assets 一起打包进 exe

# 用法：
#   pip install pyinstaller
#   pyinstaller OpenClawInstaller.spec

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
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

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
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # 如果你提供了 assets/app_icon.ico，可在此启用：
    # icon="assets/app_icon.ico",
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    a.zipfiles,
    a.metadata,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="OpenClawInstaller",
)

