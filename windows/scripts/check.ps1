#Requires -Version 7
<#
.SYNOPSIS
    Builds and tests the Windows command, song2vid.exe (S2V-025). Headless: it opens no window.

.DESCRIPTION
    1. rustfmt, Clippy, a release build and the Rust tests (frame math against fixtures/frame-math.json,
       the process tests, the import-table test on the release program).
    2. Installs the release program beside the bundled FFmpeg and FFprobe and the skill.
    3. With a parity bundle from windows/tool/parity/make-bundle.sh: runs every recorded command line
       through song2vid.exe and compares stdout, stderr and the exit status with what the Mac command
       printed (previews are compared by size and by the colour of each quadrant), then the timing
       limits, killing the program mid-job, cancelling on standard input, and an output held open.

    The toolchain is pinned: x86_64-pc-windows-msvc, Rust 1.97.1 by default. Nothing is installed.

.EXAMPLE
    .\check.ps1 -Staging C:\scratch\staging -Bundle C:\scratch\bundle
#>
param(
    # The folder with ffmpeg.exe and ffprobe.exe, either itself or as <folder>\bin\win32-x64.
    [Parameter(Mandatory)][string] $Staging,
    # The parity bundle (make-bundle.sh output). Without it only the Rust checks run.
    [string] $Bundle,
    [string] $Toolchain = '1.97.1',
    [string] $Source = (Join-Path $PSScriptRoot '..\tool'),
    # Where build output and installed copies go. Created if missing, left in place afterwards.
    [string] $Work = (Join-Path ([System.IO.Path]::GetTempPath()) 'song2vid-check')
)

$ErrorActionPreference = 'Stop'
$Source = (Resolve-Path $Source).Path
$Staging = (Resolve-Path $Staging).Path
$helpers = if (Test-Path (Join-Path $Staging 'ffmpeg.exe')) { $Staging } else { Join-Path $Staging 'bin\win32-x64' }
foreach ($name in 'ffmpeg.exe', 'ffprobe.exe') {
    if (-not (Test-Path (Join-Path $helpers $name))) { throw "$name is not in $helpers" }
}
New-Item -ItemType Directory -Force $Work | Out-Null
$Work = (Resolve-Path $Work).Path
$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Native([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program $($Arguments -join ' ') exited $LASTEXITCODE" }
}

function Fail([string] $Message) {
    $failures.Add($Message)
    Write-Output "FAIL: $Message"
}

# ---- 1. The Rust checks --------------------------------------------------------------------------
Write-Output "== Rust $Toolchain, x86_64-pc-windows-msvc"
$env:CARGO_TARGET_DIR = Join-Path $Work 'target'
$env:SONG2VID_TEST_FFMPEG_DIR = $helpers
Push-Location $Source
try {
    Invoke-Native rustc @("+$Toolchain", '-V')
    Invoke-Native cargo @("+$Toolchain", '-V')
    Invoke-Native cargo @("+$Toolchain", 'fmt', '--check')
    Invoke-Native cargo @("+$Toolchain", 'clippy', '--locked', '--all-targets', '--target', 'x86_64-pc-windows-msvc', '--', '-D', 'warnings')
    Invoke-Native cargo @("+$Toolchain", 'build', '--locked', '--release', '--target', 'x86_64-pc-windows-msvc')
    $release = Join-Path $env:CARGO_TARGET_DIR 'x86_64-pc-windows-msvc\release\song2vid.exe'
    $env:SONG2VID_IMPORT_CHECK = $release
    Invoke-Native cargo @("+$Toolchain", 'test', '--locked', '--target', 'x86_64-pc-windows-msvc', '--', '--nocapture', '--test-threads=4')
}
finally {
    Pop-Location
    Remove-Item Env:SONG2VID_IMPORT_CHECK -ErrorAction SilentlyContinue
}
$size = (Get-Item $release).Length
Write-Output "Rust checks passed. Release program: $size bytes."

# ---- 2. An installed copy ------------------------------------------------------------------------
$install = Join-Path $Work 'install'
if (Test-Path $install) { Remove-Item -Recurse -Force $install }
New-Item -ItemType Directory $install | Out-Null
Copy-Item $release (Join-Path $install 'song2vid.exe')
Copy-Item (Join-Path $helpers 'ffmpeg.exe') $install
Copy-Item (Join-Path $helpers 'ffprobe.exe') $install
$exe = Join-Path $install 'song2vid.exe'

if (-not $Bundle) {
    Write-Output 'No parity bundle was given: the Mac comparison, the timing and the process checks were not run.'
    Write-Output 'check: Rust checks passed'
    exit 0
}
$Bundle = (Resolve-Path $Bundle).Path
$media = Join-Path $Bundle 'media'
if (Test-Path (Join-Path $Bundle 'SKILL.md')) { Copy-Item (Join-Path $Bundle 'SKILL.md') $install }

# ---- Helpers for running the program ---------------------------------------------------------------
Add-Type -AssemblyName System.Drawing

function Read-AllBytes([System.IO.Stream] $Stream) {
    $memory = New-Object System.IO.MemoryStream
    $Stream.CopyTo($memory)
    , $memory.ToArray()
}

# Runs the program with the given arguments. Standard input is closed unless -OpenInput is given.
# Returns the exact bytes of both streams and the exit status; the environment holds a planted value
# that no output may contain.
function Start-Song2Vid([string[]] $Arguments, [string] $WorkingDirectory, [switch] $OpenInput) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Environment['S2V_PLANTED'] = 'planted-fake-environment-value'
    $process = [System.Diagnostics.Process]::Start($info)
    if (-not $OpenInput) { $process.StandardInput.Close() }
    $out = New-Object System.IO.MemoryStream
    $err = New-Object System.IO.MemoryStream
    [pscustomobject]@{
        Process  = $process
        OutTask  = $process.StandardOutput.BaseStream.CopyToAsync($out)
        ErrTask  = $process.StandardError.BaseStream.CopyToAsync($err)
        Out      = $out
        Err      = $err
        Started  = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

function Wait-Song2Vid($Run, [int] $Milliseconds = 120000) {
    if (-not $Run.Process.WaitForExit($Milliseconds)) { $Run.Process.Kill($true); throw 'song2vid.exe did not finish' }
    $Run.Process.WaitForExit()
    $Run.OutTask.Wait(); $Run.ErrTask.Wait()
    [pscustomobject]@{
        Status  = $Run.Process.ExitCode
        Stdout  = $Run.Out.ToArray()
        Stderr  = $Run.Err.ToArray()
        Seconds = $Run.Started.Elapsed.TotalSeconds
    }
}

function Invoke-Song2Vid([string[]] $Arguments, [string] $WorkingDirectory = $media) {
    Wait-Song2Vid (Start-Song2Vid $Arguments $WorkingDirectory)
}

function Test-SameBytes([byte[]] $A, [byte[]] $B) {
    [System.Convert]::ToBase64String($A) -ceq [System.Convert]::ToBase64String($B)
}

function ConvertTo-Text([byte[]] $Bytes) { [System.Text.Encoding]::UTF8.GetString($Bytes) }

# The size and the colour at the middle of each quadrant of a picture.
function Get-Quadrants([string] $Path) {
    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width; $h = $bitmap.Height
        $colours = foreach ($point in @(@(($w / 4), ($h / 4)), @((3 * $w / 4), ($h / 4)), @(($w / 4), (3 * $h / 4)), @((3 * $w / 4), (3 * $h / 4)))) {
            $c = $bitmap.GetPixel([int]$point[0], [int]$point[1])
            , @([int]$c.R, [int]$c.G, [int]$c.B)
        }
        [pscustomobject]@{ Size = "${w}x${h}"; Colours = $colours }
    }
    finally { $bitmap.Dispose() }
}

function Get-LeakProblem([string] $Text) {
    foreach ($forbidden in 'planted-fake-environment-value', $Bundle, $media, $Work, '\\?\', '\Users\') {
        if ($forbidden -and $Text.Contains($forbidden)) { return "output holds '$forbidden'" }
    }
    $null
}

# ---- 3. The program's own answers ------------------------------------------------------------------
Write-Output '== version, repo and skill'
$run = Invoke-Song2Vid @('--version')
if ((ConvertTo-Text $run.Stdout) -cne "song2vid 1.2.0`n" -or $run.Status -ne 0) { Fail "-v printed '$(ConvertTo-Text $run.Stdout)' ($($run.Status))" }
if (Test-Path (Join-Path $install 'SKILL.md')) {
    $skill = Invoke-Song2Vid @('-S')
    if (-not (Test-SameBytes $skill.Stdout ([System.IO.File]::ReadAllBytes((Join-Path $install 'SKILL.md')))) -or $skill.Status -ne 0) {
        Fail '-S does not print the skill byte for byte'
    }
}

# ---- 4. Every recorded command line, compared with the Mac command ---------------------------------
Write-Output '== Parity with the Mac command'
$cases = Get-Content (Join-Path $Bundle 'cases.tsv')
New-Item -ItemType Directory -Force (Join-Path $media 'out') | Out-Null
$compared = 0; $previews = 0; $failedCases = 0
foreach ($line in $cases) {
    $parts = $line -split "`t"
    $mode = $parts[0]; $id = $parts[1]
    $arguments = if ($parts.Count -gt 2) { @($parts[2..($parts.Count - 1)] | Where-Object { $_ -ne '' }) } else { @() }
    $expectedOut = [System.IO.File]::ReadAllBytes((Join-Path $Bundle "expected\$id.out"))
    $expectedErr = [System.IO.File]::ReadAllBytes((Join-Path $Bundle "expected\$id.err"))
    $expectedStatus = [int](Get-Content (Join-Path $Bundle "expected\$id.status") -Raw).Trim()
    $result = Invoke-Song2Vid $arguments
    $problem = $null
    if ($result.Status -ne $expectedStatus) { $problem = "exit status $($result.Status), the Mac command gave $expectedStatus" }
    elseif (-not (Test-SameBytes $result.Stderr $expectedErr)) { $problem = 'stderr differs' }
    elseif ($mode -eq 'approx-length') {
        $ours = (ConvertTo-Text $result.Stdout) | ConvertFrom-Json
        $theirs = (ConvertTo-Text $expectedOut) | ConvertFrom-Json
        $difference = [math]::Abs($ours.audio.duration_seconds - $theirs.audio.duration_seconds)
        $ours.audio.duration_seconds = 0; $theirs.audio.duration_seconds = 0
        if (($ours | ConvertTo-Json -Depth 8 -Compress) -cne ($theirs | ConvertTo-Json -Depth 8 -Compress)) { $problem = 'JSON differs apart from the length' }
        elseif ($difference -gt 0.1) { $problem = "length differs by $difference s" }
    }
    elseif (-not (Test-SameBytes $result.Stdout $expectedOut)) { $problem = 'stdout differs' }
    if (-not $problem) { $problem = Get-LeakProblem ((ConvertTo-Text $result.Stdout) + (ConvertTo-Text $result.Stderr)) }
    if (-not $problem -and $mode -eq 'preview') {
        $previews++
        $mine = Get-Quadrants (Join-Path $media "out\$id.png")
        $theirs = Get-Quadrants (Join-Path $Bundle "expected\$id.png")
        if ($mine.Size -ne $theirs.Size) { $problem = "picture is $($mine.Size), the Mac's is $($theirs.Size)" }
        else {
            for ($q = 0; $q -lt 4; $q++) {
                for ($c = 0; $c -lt 3; $c++) {
                    if ([math]::Abs($mine.Colours[$q][$c] - $theirs.Colours[$q][$c]) -gt 24) {
                        $problem = "quadrant $q colour ($($mine.Colours[$q] -join ',')) differs from the Mac's ($($theirs.Colours[$q] -join ','))"
                    }
                }
            }
        }
    }
    $compared++
    if ($problem) {
        $failedCases++
        Fail "case ${id}: $problem. Arguments: $($arguments -join ' ')"
        Write-Output "  ours:   $((ConvertTo-Text $result.Stdout).Trim()) $((ConvertTo-Text $result.Stderr).Trim())"
        Write-Output "  the Mac: $((ConvertTo-Text $expectedOut).Trim()) $((ConvertTo-Text $expectedErr).Trim())"
    }
}
Write-Output "Compared $compared command lines ($previews with pictures): $failedCases differ."

# ---- 5. Timing (SPEC section 26.4) -----------------------------------------------------------------
$perf = Join-Path $Bundle 'perf'
if (Test-Path $perf) {
    Write-Output '== Timing: check and preview within 3 seconds'
    $timed = @(
        @('check', 'ten-minutes.wav'), @('check', 'ten-minutes.mp3'), @('check', 'ten-minutes.m4a'),
        @('check', 'noise-50mb.png'), @('preview', 'noise-50mb.png', '-o', (Join-Path $Work 'noise-preview.png'), '-w')
    )
    foreach ($arguments in $timed) {
        $result = Invoke-Song2Vid $arguments $perf
        $label = $arguments -join ' '
        Write-Output ('  {0:n2} s (exit {1}): {2}' -f $result.Seconds, $result.Status, ($label -replace [regex]::Escape($Work), '<work>'))
        if ($result.Status -ne 0) { Fail "'$label' exited $($result.Status)" }
        elseif ($result.Seconds -gt 3) { Fail "'$label' took $([math]::Round($result.Seconds, 2)) s, over 3" }
    }
}

# ---- 6. Children die with the program, cancel on input, and an output held open ----------------------
function Get-Children([string] $Needle) {
    @(Get-CimInstance Win32_Process -Filter "Name = 'ffmpeg.exe' OR Name = 'ffprobe.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Needle) })
}

if (Test-Path (Join-Path $perf 'slow-14000.png')) {
    Write-Output '== Killing song2vid.exe mid-job leaves no FFmpeg'
    $slowOut = Join-Path $Work 'slow-preview.png'
    $run = Start-Song2Vid @('preview', (Join-Path $perf 'slow-14000.png'), '-o', $slowOut, '-w') $perf
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline -and (Get-Children 'slow-14000').Count -eq 0) { Start-Sleep -Milliseconds 20 }
    $before = (Get-Children 'slow-14000').Count
    if ($before -eq 0) { Fail 'no FFmpeg or FFprobe child appeared for the slow picture' }
    Start-Sleep -Milliseconds 300
    Stop-Process -Id $run.Process.Id -Force
    $killed = [System.Diagnostics.Stopwatch]::StartNew()
    while ($killed.Elapsed.TotalSeconds -lt 2 -and (Get-Children 'slow-14000').Count -gt 0) { Start-Sleep -Milliseconds 50 }
    $left = (Get-Children 'slow-14000').Count
    Write-Output ("  {0} child(ren) before the kill, {1} left after {2:n2} s" -f $before, $left, $killed.Elapsed.TotalSeconds)
    if ($left -ne 0) { Fail "$left FFmpeg or FFprobe process(es) were still alive 2 seconds after the kill" }
    Get-Children 'slow-14000' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if (Test-Path $slowOut) { Fail 'a killed run left an output file' }

    Write-Output '== --cancel-on-eof cancels within 2 seconds and leaves no file'
    foreach ($how in 'end of input', 'cancel line') {
        $folder = Join-Path $Work "cancel-$($how -replace ' ', '-')"
        if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
        New-Item -ItemType Directory $folder | Out-Null
        $run = Start-Song2Vid @('preview', (Join-Path $perf 'slow-14000.png'), '-o', (Join-Path $folder 'out.png'), '-w', '-j', '-E') $perf -OpenInput
        Start-Sleep -Seconds 1
        if ($run.Process.HasExited) { Fail "the slow preview ended before the cancel ($how)" ; continue }
        $asked = [System.Diagnostics.Stopwatch]::StartNew()
        if ($how -eq 'end of input') { $run.Process.StandardInput.Close() }
        else { $run.Process.StandardInput.Write("ignore cancel`ncan"); $run.Process.StandardInput.Write("cel`r`n"); $run.Process.StandardInput.Flush() }
        $result = Wait-Song2Vid $run 10000
        $took = $asked.Elapsed.TotalSeconds
        $text = ConvertTo-Text $result.Stdout
        Write-Output ('  {0}: exit {1} after {2:n2} s' -f $how, $result.Status, $took)
        if ($result.Status -ne 130 -or -not $text.Contains('"code":"cancelled"')) { Fail "$how did not cancel: exit $($result.Status) $text" }
        if ($took -gt 2) { Fail "$how took $([math]::Round($took, 2)) s to cancel" }
        if (@(Get-ChildItem -Force $folder).Count -ne 0) { Fail "$how left files: $((Get-ChildItem -Force $folder).Name -join ', ')" }
        if ((Get-Children 'slow-14000').Count -ne 0) { Fail "$how left FFmpeg running" }
    }
}

Write-Output '== An output another program holds open is output_in_use after 2 seconds'
$held = Join-Path $Work 'held.png'
[System.IO.File]::WriteAllText($held, 'existing output')
$stream = [System.IO.File]::Open($held, 'Open', 'Read', 'Read')
try {
    $result = Invoke-Song2Vid @('preview', 'fit-1000x800.png', '-o', $held, '-w', '-j')
    $text = ConvertTo-Text $result.Stdout
    Write-Output ('  exit {0} after {1:n2} s' -f $result.Status, $result.Seconds)
    if ($result.Status -ne 4 -or -not $text.Contains('"code":"output_in_use"')) { Fail "a held output gave exit $($result.Status): $text" }
    if ($result.Seconds -lt 1.8 -or $result.Seconds -gt 5) { Fail "the wait for a held output was $([math]::Round($result.Seconds, 2)) s" }
}
finally { $stream.Dispose() }
if ([System.IO.File]::ReadAllText($held) -ne 'existing output') { Fail 'a held output was changed' }
if (@(Get-ChildItem -Force $Work -Filter '.song2vid-*').Count -ne 0) { Fail 'a temporary file was left beside the held output' }

Write-Output '== --update against the live release list (reports only)'
$result = Invoke-Song2Vid @('--update', '--json')
Write-Output ('  exit {0}: {1}' -f $result.Status, (ConvertTo-Text $result.Stdout).Trim())
if ($result.Status -ne 0 -and $result.Status -ne 5) { Fail "--update exited $($result.Status)" }

if ($failures.Count -gt 0) {
    Write-Output "check: $($failures.Count) problem(s)"
    $failures | ForEach-Object { Write-Output "  $_" }
    exit 1
}
Write-Output 'check: all passed'
