import pathlib, subprocess, shutil, time, re, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text(encoding='utf-8').strip()
source = (root / 'battery-tooltip.wh.cpp').read_text(encoding='utf-8')
declared = re.search(r'^// @version\s+(\S+)', source, re.MULTILINE)
if not declared or declared.group(1) != version:
    raise ValueError('VERSION and the mod metadata must match')
runtime = root / 'runtime/windhawk'
compiler = runtime / 'Compiler'
out = runtime / 'AppData/Engine/Mods/64'
out.mkdir(parents=True, exist_ok=True)
filename = f'battery-tooltip_{version}_{time.time_ns()}.dll'
args = [str(compiler / 'bin/clang++.exe'), '-std=c++23', '-O2', '-shared',
        '-DUNICODE', '-D_UNICODE', '-DWINVER=0x0A00', '-D_WIN32_WINNT=0x0A00',
        '-D_WIN32_IE=0x0A00', '-DNTDDI_VERSION=0x0A000008', '-D__USE_MINGW_ANSI_STDIO=0',
        '-DWH_MOD', '-DWH_MOD_ID=L"local@battery-tooltip"', f'-DWH_MOD_VERSION=L"{version}"',
        str(runtime / 'Engine/1.7.3/64/windhawk.lib'),
        str(root / 'battery-tooltip.wh.cpp'), '-include', 'windhawk_api.h',
        '-target', 'x86_64-w64-mingw32', '-Wl,--export-all-symbols',
        '-lruntimeobject', '-lole32', '-loleaut32', '-lcomctl32',
        '-o', str(out / filename)]
subprocess.run(args, cwd=compiler, check=True)
for source, dest in [('libc++.dll','libc++.whl'), ('libunwind.dll','libunwind.whl'), ('windhawk-mod-shim.dll','windhawk-mod-shim.dll')]:
    shutil.copy2(compiler / 'x86_64-w64-mingw32/bin' / source, out / dest)
mods = out.parent
config = '''[Mod]
LibraryFileName=PLACEHOLDER
Disabled=1
LoggingEnabled=1
DebugLoggingEnabled=0
Include=explorer.exe
Exclude=
Architecture=x86-64
Version=VERSION_PLACEHOLDER
[Settings]
language=auto
previewMode=0
chargeTargetPercent=100
'''.replace('VERSION_PLACEHOLDER',version).replace('PLACEHOLDER',filename)
with tempfile.NamedTemporaryFile(mode='w',encoding='utf-8',suffix='.tmp',dir=mods,delete=False) as staged:
    staged.write(config)
    staged_path = pathlib.Path(staged.name)
try:
    subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',
        str(root/'tools/SaveConfig.ps1'),'-Path',str(mods/'local@battery-tooltip.ini'),
        '-Source',str(staged_path)],check=True)
finally:
    staged_path.unlink(missing_ok=True)
sources = runtime / 'AppData/ModsSource'
sources.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'battery-tooltip.wh.cpp', sources / 'local@battery-tooltip.wh.cpp')
print(out / filename)
