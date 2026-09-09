<#
  Local build + run of the AngelScript checker (Windows, no admin installs).

  Uses the MSVC toolset from Visual Studio (found via vswhere) and a portable
  CMake downloaded once to %LOCALAPPDATA%\op-asrun-cache. AngelScript itself is
  fetched by CMake (FetchContent) into the build tree.

    tools\as\check.ps1              # regenerate stubs, build, --compile + --test
    tools\as\check.ps1 -NoTest      # compile gate only
    tools\as\check.ps1 -Clean       # wipe the build tree first
#>
[CmdletBinding()]
param([switch]$NoTest, [switch]$Clean)

$ErrorActionPreference = 'Stop'
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$plugin = Resolve-Path (Join-Path $here '..\..')
# Build tree lives OUTSIDE the plugin folder: the dev install may symlink this
# repo into the Openplanet plugins dir, and Openplanet would try to compile the
# AngelScript SDK sources CMake fetches into _deps/ (see tools/as/README.md).
$cache = Join-Path $env:LOCALAPPDATA 'op-asrun-cache'
$build = Join-Path $cache 'build'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

function Find-Python {
  foreach ($c in 'py -3','python3','python') {
    $exe, $rest = $c.Split(' ',2)
    if (Get-Command $exe -ErrorAction SilentlyContinue) { return $c }
  }
  throw "python not found on PATH"
}

function Get-CMake {
  $sys = Get-Command cmake -ErrorAction SilentlyContinue
  if ($sys) { return $sys.Source }
  $ver = '3.30.5'
  $dir = Join-Path $cache "cmake-$ver-windows-x86_64"
  $exe = Join-Path $dir 'bin\cmake.exe'
  if (-not (Test-Path $exe)) {
    $zip = Join-Path $cache "cmake-$ver.zip"
    Write-Host "downloading portable CMake $ver ..."
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
      "https://github.com/Kitware/CMake/releases/download/v$ver/cmake-$ver-windows-x86_64.zip"
    Expand-Archive -Force $zip $cache
    Remove-Item $zip
  }
  return $exe
}

$py    = Find-Python
$cmake = Get-CMake

# Generated stub also goes outside the plugin folder (gen_stubs.py + asrun read $ASRUN_GEN).
$env:ASRUN_GEN = Join-Path $cache 'generated'
New-Item -ItemType Directory -Force -Path $env:ASRUN_GEN | Out-Null

Write-Host "== regenerating stubs ==" -ForegroundColor Cyan
& ([scriptblock]::Create("$py `"$here\gen_stubs.py`""))
if ($LASTEXITCODE) { throw "gen_stubs.py failed" }

if ($Clean -and (Test-Path $build)) { Remove-Item -Recurse -Force $build }

Write-Host "== configuring ==" -ForegroundColor Cyan
& $cmake -S $here -B $build -G "Visual Studio 17 2022" -A x64 -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE) { throw "cmake configure failed" }

Write-Host "== building ==" -ForegroundColor Cyan
& $cmake --build $build --config Release --parallel
if ($LASTEXITCODE) { throw "build failed" }

$asrun = Join-Path $build 'Release\asrun.exe'
if (-not (Test-Path $asrun)) { $asrun = Join-Path $build 'asrun.exe' }

# asrun writes compile diagnostics to stderr; don't let PowerShell treat that as
# a terminating error.
$ErrorActionPreference = 'Continue'

Write-Host "== asrun --compile ==" -ForegroundColor Cyan
& $asrun --compile (Join-Path $plugin 'src') 2>&1 | ForEach-Object { "$_" }
$compileExit = $LASTEXITCODE

$testExit = 0
if (-not $NoTest) {
  Write-Host "== asrun --test ==" -ForegroundColor Cyan
  & $asrun --test (Join-Path $plugin 'src') (Join-Path $here 'tests') 2>&1 | ForEach-Object { "$_" }
  $testExit = $LASTEXITCODE
}
$ErrorActionPreference = 'Stop'

if ($compileExit -or $testExit) {
  Write-Host "FAILED (compile=$compileExit test=$testExit)" -ForegroundColor Red
  exit 1
}
Write-Host "OK" -ForegroundColor Green
