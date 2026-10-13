import pathlib, subprocess
root = pathlib.Path(__file__).resolve().parent.parent
compiler = root / 'runtime/windhawk/Compiler'
out = root / 'artifacts/format-tests.exe'
out.parent.mkdir(exist_ok=True)
subprocess.run([str(compiler/'bin/clang++.exe'), '-std=c++23', '-O2', '-static',
    '-target', 'x86_64-w64-mingw32', str(root/'tests/FormatTests.cpp'), '-o', str(out)],
    cwd=compiler, check=True)
subprocess.run([str(out)], check=True)
