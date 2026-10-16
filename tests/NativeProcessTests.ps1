$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\native-process-tests-' + [Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$test = Join-Path $root 'process fixture.exe'
& $compiler /nologo /target:exe /platform:x64 /reference:Microsoft.CSharp.dll "/out:$test" (Join-Path $PSScriptRoot 'NativeProcessTests.cs') (Join-Path $PSScriptRoot '..\tools\NativeProcess.cs')
if ($LASTEXITCODE -ne 0) { throw 'Native process test build failed.' }
& $compiler /nologo /target:winexe /platform:x64 /reference:Microsoft.CSharp.dll "/out:$root\GUI fixture.exe" (Join-Path $PSScriptRoot 'NativeProcessTests.cs') (Join-Path $PSScriptRoot '..\tools\NativeProcess.cs')
if ($LASTEXITCODE -ne 0) { throw 'GUI process test build failed.' }
& $test $root
if ($LASTEXITCODE -ne 0) { throw 'Native process tests failed.' }
