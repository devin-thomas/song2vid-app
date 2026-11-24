#Requires -Version 7
<#
.SYNOPSIS
    Builds and tests the Windows command, song2vid.exe (S2V-025, S2V-026). Headless: it opens no window.

.DESCRIPTION
    1. rustfmt, Clippy, a release build and the Rust tests (frame math against fixtures/frame-math.json,
       the process tests, the import-table test on the release program).
    2. Installs the release program beside the bundled FFmpeg and FFprobe and the skill.
    3. With a parity bundle from windows/tool/parity/make-bundle.sh: runs every recorded command line
       through song2vid.exe and compares stdout, stderr and the exit status with what the Mac command
       printed (previews are compared by size and by the colour of each quadrant; `make --dry-run`
       and the checks before encoding are compared with the Encoder's names swapped), then makes
       each of the Mac command's videos again and checks size, codec, tags and length against it,
       then the timing limits, killing the program mid-job (while it prepares the picture, encodes
       the group and writes the song), cancelling on standard input and with Ctrl-C in a console,
       progress in the live, plain and JSON forms, and an output held open or already there.
       The videos are left in <Work>\videos: compare-videos.sh compares them with the Mac's by SSIM.

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
function Start-Song2Vid([string[]] $Arguments, [string] $WorkingDirectory, [switch] $OpenInput, [hashtable] $Environment = @{}) {
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
    foreach ($name in $Environment.Keys) { $info.Environment[$name] = $Environment[$name] }
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

function Invoke-Song2Vid([string[]] $Arguments, [string] $WorkingDirectory = $media, [hashtable] $Environment = @{}) {
    Wait-Song2Vid (Start-Song2Vid $Arguments $WorkingDirectory -Environment $Environment)
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
    # The Mac's Encoder is Apple's; this computer's is the software one, forced so the answer does not
    # depend on the hardware (the hardware Encoders are S2V-027's).
    if ($mode -eq 'make-dry') {
        $result = Invoke-Song2Vid $arguments $media @{ SONG2VID_TEST_ENCODER = 'software' }
        $expectedOut = [System.Text.Encoding]::UTF8.GetBytes(((ConvertTo-Text $expectedOut).Replace('Apple encoder', 'software encoder').Replace('"encoder":"apple"', '"encoder":"software"')))
    }
    else { $result = Invoke-Song2Vid $arguments }
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

# ---- 4b. make: the Mac command's videos, made again ------------------------------------------------
$videosFile = Join-Path $Bundle 'videos.tsv'
$videoOut = Join-Path $Work 'videos'
$ffprobe = Join-Path $install 'ffprobe.exe'

function Get-Probe([string] $Path) {
    $text = (& $ffprobe -v error -show_streams -show_format -print_format json $Path) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "ffprobe failed on $Path" }
    $text | ConvertFrom-Json
}

# What must be the same as the Mac command's video, and what must be right whatever the Mac made.
function Get-VideoProblem($Mine, $Theirs, $Result, $MacResult) {
    $video = @($Mine.streams | Where-Object { $_.codec_type -eq 'video' })
    $audio = @($Mine.streams | Where-Object { $_.codec_type -eq 'audio' })
    $macVideo = @($Theirs.streams | Where-Object { $_.codec_type -eq 'video' })
    $macAudio = @($Theirs.streams | Where-Object { $_.codec_type -eq 'audio' })
    if ($video.Count -ne 1 -or $audio.Count -ne 1) { return "$($video.Count) video and $($audio.Count) audio streams" }
    $v = $video[0]; $a = $audio[0]; $mv = $macVideo[0]; $ma = $macAudio[0]
    if ($v.codec_name -ne 'h264' -or $v.profile -ne 'High') { return "video is $($v.codec_name) $($v.profile)" }
    if ($v.width -ne $mv.width -or $v.height -ne $mv.height) { return "size $($v.width)x$($v.height), the Mac's is $($mv.width)x$($mv.height)" }
    if ($v.pix_fmt -ne 'yuv420p') { return "pixel format $($v.pix_fmt)" }
    if ($v.color_space -ne 'bt709' -or $v.color_primaries -ne 'bt709' -or $v.color_transfer -ne 'bt709' -or $v.color_range -ne 'tv') {
        return "colour tags $($v.color_space)/$($v.color_primaries)/$($v.color_transfer)/$($v.color_range)"
    }
    if ($v.r_frame_rate -ne '30/1') { return "frame rate $($v.r_frame_rate)" }
    if ($a.codec_name -ne 'aac' -or $a.sample_rate -ne $ma.sample_rate -or $a.channels -ne $ma.channels) {
        return "audio is $($a.codec_name) $($a.sample_rate) Hz $($a.channels) ch, the Mac's is $($ma.sample_rate) Hz $($ma.channels) ch"
    }
    $lengths = @([double]$Mine.format.duration, [double]$Theirs.format.duration, [double]$MacResult.output.duration_seconds)
    foreach ($length in $lengths[1..2]) { if ([math]::Abs($lengths[0] - $length) -gt 0.1) { return "length $($lengths[0]) s against $length s" } }
    if ([math]::Abs([double]$v.duration - [double]$mv.duration) -gt 0.1) { return "video length $($v.duration) s, the Mac's is $($mv.duration) s" }
    foreach ($key in 'width', 'height') {
        if ($Result.output.$key -ne $MacResult.output.$key) { return "result $key $($Result.output.$key), the Mac's is $($MacResult.output.$key)" }
    }
    foreach ($key in 'placement', 'enlarged', 'codec') {
        if ($Result.$key -ne $MacResult.$key) { return "result $key $($Result.$key), the Mac's is $($MacResult.$key)" }
    }
    if ([math]::Abs([double]$Result.output.duration_seconds - [double]$MacResult.output.duration_seconds) -gt 0.1) { return 'result length differs' }
    if ($Result.output.bytes -ne (Get-Item $Mine.format.filename).Length) { return 'result bytes is not the file size' }
    $null
}

if (Test-Path $videosFile) {
    Write-Output "== make: the Mac command's videos, made again"
    if (Test-Path $videoOut) { Remove-Item -Recurse -Force $videoOut }
    New-Item -ItemType Directory $videoOut | Out-Null
    $madeVideos = 0
    foreach ($line in Get-Content $videosFile) {
        $id, $song, $image, $shape, $resolution = $line -split "`t"
        $arguments = @('make', $song, $image, '-s', $shape)
        if ($resolution -ne '-') { $arguments += @('-r', $resolution) }
        $arguments += @('-o', (Join-Path $videoOut "$id.mp4"), '--json')
        $result = Invoke-Song2Vid $arguments $media @{ SONG2VID_TEST_ENCODER = 'software' }
        $text = ConvertTo-Text $result.Stdout
        $problem = Get-LeakProblem ($text + (ConvertTo-Text $result.Stderr))
        if (-not $problem -and $result.Status -ne 0) { $problem = "exit status $($result.Status): $($text.Trim())" }
        if (-not $problem -and $result.Stderr.Length -ne 0) { $problem = 'standard error is not empty under --json' }
        if (-not $problem) {
            try {
                $lines = @($text -split "`n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
                if ($lines[-1].type -ne 'result' -or @($lines | Where-Object { $_.type -eq 'result' }).Count -ne 1) { $problem = 'not exactly one result, last' }
                $macResult = Get-Content (Join-Path $Bundle "videos\$id.json") -Raw | ConvertFrom-Json
                if (-not $problem) {
                    $problem = Get-VideoProblem (Get-Probe (Join-Path $videoOut "$id.mp4")) (Get-Content (Join-Path $Bundle "videos\$id.probe.json") -Raw | ConvertFrom-Json) $lines[-1] $macResult
                }
            }
            catch { $problem = "could not be checked: $($_.Exception.Message)" }
        }
        $madeVideos++
        Write-Output ('  {0}: {1:n1} s{2}' -f $id, $result.Seconds, $(if ($problem) { " FAIL $problem" } else { '' }))
        if ($problem) { Fail "video ${id}: $problem" }
    }
    $leftovers = @(Get-ChildItem -Force $videoOut -Filter '.song2vid-*')
    if ($leftovers.Count -ne 0) { Fail "temporary files were left: $($leftovers.Name -join ', ')" }
    Write-Output "Made $madeVideos videos. Their SSIM against the Mac's is compared on the Mac: copy $videoOut and run windows/tool/parity/compare-videos.sh."
}

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

# A program run under a pseudo console (ConPTY): it sees a real console, so the live line, the
# virtual terminal sequences and Ctrl-C all work as they do in Windows Terminal, and no window opens.
$ptySource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public sealed class PtyRun : IDisposable
{
    [StructLayout(LayoutKind.Sequential)] struct COORD { public short X; public short Y; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO
    {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX; public int dwY; public int dwXSize; public int dwYSize; public int dwXCountChars; public int dwYCountChars;
        public int dwFillAttribute; public int dwFlags; public short wShowWindow; public short cbReserved2;
        public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
    }
    [StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

    [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(COORD size, SafeFileHandle input, SafeFileHandle output, uint flags, out IntPtr console);
    [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr console);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out SafeFileHandle read, out SafeFileHandle write, IntPtr attributes, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string application, StringBuilder commandLine, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref STARTUPINFOEX startup, out PROCESS_INFORMATION info);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr handle, out uint code);
    [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr handle, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    IntPtr console, process;
    FileStream input;
    FileStream output;
    readonly StringBuilder text = new StringBuilder();
    Thread reader;

    public static PtyRun Start(string commandLine, string directory)
    {
        var run = new PtyRun();
        SafeFileHandle inputRead, inputWrite, outputRead, outputWrite;
        if (!CreatePipe(out inputRead, out inputWrite, IntPtr.Zero, 0)) throw new InvalidOperationException("CreatePipe");
        if (!CreatePipe(out outputRead, out outputWrite, IntPtr.Zero, 0)) throw new InvalidOperationException("CreatePipe");
        int made = CreatePseudoConsole(new COORD { X = 120, Y = 30 }, inputRead, outputWrite, 0, out run.console);
        if (made != 0) throw new InvalidOperationException("CreatePseudoConsole " + made);
        inputRead.Dispose(); outputWrite.Dispose();
        run.input = new FileStream(inputWrite, FileAccess.Write, 1, false);
        run.output = new FileStream(outputRead, FileAccess.Read, 4096, false);

        var startup = new STARTUPINFOEX();
        startup.StartupInfo.cb = Marshal.SizeOf<STARTUPINFOEX>();
        IntPtr size = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        startup.lpAttributeList = Marshal.AllocHGlobal(size);
        if (!InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, ref size)) throw new InvalidOperationException("InitializeProcThreadAttributeList");
        if (!UpdateProcThreadAttribute(startup.lpAttributeList, 0, (IntPtr)0x20016, run.console, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) throw new InvalidOperationException("UpdateProcThreadAttribute");
        PROCESS_INFORMATION info;
        if (!CreateProcessW(null, new StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, false, 0x00080000, IntPtr.Zero, directory, ref startup, out info))
            throw new InvalidOperationException("CreateProcessW " + Marshal.GetLastWin32Error());
        run.process = info.hProcess;
        CloseHandle(info.hThread);
        run.reader = new Thread(run.Pump) { IsBackground = true };
        run.reader.Start();
        return run;
    }

    void Pump()
    {
        var bytes = new byte[4096];
        var decoder = Encoding.UTF8.GetDecoder();
        var chars = new char[8192];
        try
        {
            while (true)
            {
                int count = output.Read(bytes, 0, bytes.Length);
                if (count <= 0) return;
                int made = decoder.GetChars(bytes, 0, count, chars, 0);
                lock (text) text.Append(chars, 0, made);
            }
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }

    public void Write(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        input.Write(bytes, 0, bytes.Length);
        input.Flush();
    }

    public bool WaitForExit(int milliseconds) { return WaitForSingleObject(process, (uint)milliseconds) == 0; }

    public int ExitCode { get { uint code; GetExitCodeProcess(process, out code); return unchecked((int)code); } }

    public string Output() { lock (text) return text.ToString(); }

    public void Dispose()
    {
        if (process != IntPtr.Zero)
        {
            if (WaitForSingleObject(process, 0) != 0) TerminateProcess(process, 1);
            CloseHandle(process); process = IntPtr.Zero;
        }
        if (console != IntPtr.Zero)
        {
            // The pseudo console closes its output when it is closed; the reader ends with it.
            var closer = new Thread(() => ClosePseudoConsole(console)) { IsBackground = true };
            closer.Start(); closer.Join(3000);
            console = IntPtr.Zero;
        }
        if (input != null) { try { input.Dispose(); } catch (IOException) { } }
        if (reader != null) reader.Join(2000);
        if (output != null) { try { output.Dispose(); } catch (IOException) { } }
    }
}
'@

# ---- 7. make: speed, children, cancel, progress and publication --------------------------------------
$song3 = Join-Path $perf 'three-minutes.wav'
$scene = Join-Path $media 'scene-1600x1200.png'
$software = @{ SONG2VID_TEST_ENCODER = 'software' }

function New-CleanFolder([string] $Name) {
    $folder = Join-Path $Work $Name
    if (Test-Path $folder) { Remove-Item -Recurse -Force $folder }
    New-Item -ItemType Directory $folder | Out-Null
    $folder
}

# The first FFmpeg child whose command line holds all of the words, waiting up to $Seconds for it.
function Wait-Child([string] $Folder, [string[]] $Words, [double] $Seconds = 30) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $found = Get-Children (Split-Path $Folder -Leaf) | Where-Object { $line = $_.CommandLine; -not ($Words | Where-Object { -not $line.Contains($_) }) }
        if ($found) { return @($found)[0] }
        Start-Sleep -Milliseconds 15
    }
    $null
}

function Stop-Leftovers([string] $Folder) {
    Get-Children (Split-Path $Folder -Leaf) | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Get-FolderNames([string] $Folder) { @(Get-ChildItem -Force $Folder | ForEach-Object { $_.Name }) }

# Peak private memory of the program and everything it started, sampled while it runs.
function Measure-Peak($Run) {
    $peak = 0L
    while (-not $Run.Process.HasExited) {
        $total = 0L
        $ids = @($Run.Process.Id) + @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($Run.Process.Id)" | ForEach-Object { $_.ProcessId })
        foreach ($id in $ids) { $p = Get-Process -Id $id -ErrorAction SilentlyContinue; if ($p) { $total += $p.PrivateMemorySize64 } }
        if ($total -gt $peak) { $peak = $total }
        Start-Sleep -Milliseconds 100
    }
    $peak
}

if ((Test-Path $song3) -and (Test-Path $scene)) {
    Write-Output '== make: a three-minute song, speed and memory (software Encoder, limit 680 MB)'
    foreach ($resolution in '480p', '1080p', '2160p') {
        $folder = New-CleanFolder "speed-$resolution"
        $run = Start-Song2Vid @('make', $song3, $scene, '-r', $resolution, '-o', (Join-Path $folder 'speed.mp4'), '-j') $media -Environment $software
        $peak = Measure-Peak $run
        $result = Wait-Song2Vid $run
        Write-Output ('  {0}: {1:n1} s, peak {2:n0} MB, exit {3}' -f $resolution, $result.Seconds, ($peak / 1MB), $result.Status)
        if ($result.Status -ne 0) { Fail "speed run at $resolution exited $($result.Status): $(ConvertTo-Text $result.Stdout)" }
        if ($peak -gt 680MB) { Fail "peak private memory at $resolution was $([math]::Round($peak / 1MB)) MB, over 680" }
        if ($resolution -eq '2160p' -and $result.Seconds -gt 30) { Fail "a three-minute 2160p video took $([math]::Round($result.Seconds, 1)) s, over 30" }
    }

    Write-Output '== make: progress in each form'
    # JSON: every line parses, a line at least every 0.5 s, stages in order, exactly one result at the end.
    $folder = New-CleanFolder 'progress-json'
    $stdoutFile = Join-Path $folder 'stdout.txt'
    $process = Start-Process -FilePath $exe -ArgumentList @('make', "`"$song3`"", "`"$scene`"", '-r', '2160p', '-o', "`"$folder\video.mp4`"", '--json') -WorkingDirectory $media -RedirectStandardOutput $stdoutFile -PassThru -NoNewWindow -Environment $software 2>$null
    if (-not $process) { $process = $null }
    $stamps = New-Object System.Collections.Generic.List[double]
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $seen = 0
    while (-not $process.HasExited) {
        $count = 0
        try { $count = @([System.IO.File]::ReadAllLines($stdoutFile)).Count } catch { }
        while ($seen -lt $count) { $stamps.Add($watch.Elapsed.TotalSeconds); $seen++ }
        Start-Sleep -Milliseconds 40
    }
    $process.WaitForExit()
    $lines = @([System.IO.File]::ReadAllLines($stdoutFile))
    while ($seen -lt $lines.Count) { $stamps.Add($watch.Elapsed.TotalSeconds); $seen++ }
    $parsed = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
    $widest = 0.0
    for ($i = 1; $i -lt $stamps.Count - 1; $i++) { if ($stamps[$i] - $stamps[$i - 1] -gt $widest) { $widest = $stamps[$i] - $stamps[$i - 1] } }
    $order = 'checking', 'preparing', 'encoding', 'finishing'
    $position = 0; $wentBack = $false
    foreach ($entry in ($parsed | Where-Object { $_.type -eq 'progress' })) {
        $stage = [array]::IndexOf($order, $entry.stage)
        if ($stage -lt $position) { $wentBack = $true }
        $position = $stage
    }
    Write-Output ('  JSON: {0} lines in {1:n1} s, widest gap {2:n2} s, exit {3}' -f $parsed.Count, $watch.Elapsed.TotalSeconds, $widest, $process.ExitCode)
    if ($process.ExitCode -ne 0) { Fail "the JSON progress run exited $($process.ExitCode)" }
    if (@($parsed | Where-Object { $_.type -eq 'result' }).Count -ne 1 -or $parsed[-1].type -ne 'result') { Fail 'the JSON run did not end with exactly one result line' }
    if (@($parsed | Where-Object { $_.api_version -ne '1' }).Count -ne 0) { Fail 'a JSON line has no api_version 1' }
    if ($widest -gt 0.6) { Fail "progress went quiet for $([math]::Round($widest, 2)) s (limit 0.5 s plus the polling)" }
    if ($wentBack) { Fail 'the stage went backwards' }
    if (@($parsed | Where-Object { $_.type -eq 'progress' -and $_.stage -eq 'encoding' -and $_.encoder -ne 'software' }).Count -ne 0) { Fail 'an encoding line does not name the Encoder' }

    # Plain: no control characters, a line at least every 2 s.
    $folder = New-CleanFolder 'progress-plain'
    $errFile = Join-Path $folder 'stderr.txt'
    $outFile = Join-Path $folder 'stdout.txt'
    $process = Start-Process -FilePath $exe -ArgumentList @('make', "`"$song3`"", "`"$scene`"", '-r', '2160p', '-o', "`"$folder\video.mp4`"") -WorkingDirectory $media -RedirectStandardError $errFile -RedirectStandardOutput $outFile -PassThru -NoNewWindow -Environment $software
    $process.WaitForExit()
    $bytes = [System.IO.File]::ReadAllBytes($errFile)
    $bad = @($bytes | Where-Object { ($_ -lt 0x20 -and $_ -ne 0x0A) -or $_ -eq 0x7F })
    $plainLines = @([System.IO.File]::ReadAllLines($errFile))
    Write-Output ('  plain: {0} lines, {1} control bytes, exit {2}' -f $plainLines.Count, $bad.Count, $process.ExitCode)
    if ($process.ExitCode -ne 0) { Fail "the plain run exited $($process.ExitCode)" }
    if ($bad.Count -ne 0) { Fail 'the plain progress holds control characters' }
    if ($plainLines.Count -lt 5 -or -not ($plainLines | Where-Object { $_ -match '^Encoding \d+% \(' })) { Fail "the plain progress is too thin: $($plainLines.Count) lines" }
    if (-not ([System.IO.File]::ReadAllText($outFile)).StartsWith('Made video.mp4 (H.264, software encoder).')) { Fail 'the plain result line is wrong' }
    $quiet = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-o', (Join-Path $folder 'quiet.mp4'), '-q') $media $software
    if ($quiet.Stderr.Length -ne 0 -or $quiet.Status -ne 0 -or -not (ConvertTo-Text $quiet.Stdout).StartsWith('Made quiet.mp4')) { Fail "--quiet is not quiet: exit $($quiet.Status), $(ConvertTo-Text $quiet.Stderr)" }

    Write-Output '== make: killing song2vid.exe at each stage leaves no FFmpeg'
    $slow = Join-Path $perf 'slow-14000.png'
    $killPoints = @(
        @('picture', $slow, '480p', @('-filter_complex')),
        @('group', $scene, '2160p', @('h264_mf')),
        @('song', $scene, '2160p', @('-stream_loop'))
    )
    foreach ($point in $killPoints) {
        $folder = New-CleanFolder "kill-$($point[0])"
        $run = Start-Song2Vid @('make', $song3, $point[1], '-r', $point[2], '-o', (Join-Path $folder 'video.mp4'), '--json') $media -Environment $software
        $child = Wait-Child $folder $point[3] 60
        if (-not $child) { Fail "no FFmpeg child appeared for the $($point[0]) stage"; Stop-Process -Id $run.Process.Id -Force -ErrorAction SilentlyContinue; continue }
        Start-Sleep -Milliseconds 200
        $before = @(Get-Children (Split-Path $folder -Leaf)).Count
        Stop-Process -Id $run.Process.Id -Force
        $killed = [System.Diagnostics.Stopwatch]::StartNew()
        while ($killed.Elapsed.TotalSeconds -lt 2 -and (Get-Children (Split-Path $folder -Leaf)).Count -gt 0) { Start-Sleep -Milliseconds 40 }
        $left = @(Get-Children (Split-Path $folder -Leaf)).Count
        Write-Output ("  {0}: {1} child(ren), {2} left after {3:n2} s" -f $point[0], $before, $left, $killed.Elapsed.TotalSeconds)
        if ($left -ne 0) { Fail "$left FFmpeg process(es) were alive 2 seconds after the kill at the $($point[0]) stage" }
        Stop-Leftovers $folder
        if (Test-Path (Join-Path $folder 'video.mp4')) { Fail "a killed run at the $($point[0]) stage left the output name" }
    }

    Write-Output '== make: --cancel-on-eof cancels within 2 seconds, leaves no file, and the next run is unaffected'
    foreach ($how in 'end of input', 'cancel line') {
        $folder = New-CleanFolder "cancel-$($how -replace ' ', '-')"
        $run = Start-Song2Vid @('make', $song3, $scene, '-r', '2160p', '-o', (Join-Path $folder 'video.mp4'), '-j', '-E') $media -OpenInput -Environment $software
        $child = Wait-Child $folder @('h264_mf') 60
        if (-not $child) { Fail "no group encode to cancel ($how)"; Stop-Process -Id $run.Process.Id -Force -ErrorAction SilentlyContinue; continue }
        Start-Sleep -Milliseconds 500
        $asked = [System.Diagnostics.Stopwatch]::StartNew()
        if ($how -eq 'end of input') { $run.Process.StandardInput.Close() }
        else { $run.Process.StandardInput.Write("ignore cancel`ncan"); $run.Process.StandardInput.Write("cel`r`n"); $run.Process.StandardInput.Flush() }
        $result = Wait-Song2Vid $run 20000
        $took = $asked.Elapsed.TotalSeconds
        $text = ConvertTo-Text $result.Stdout
        $last = @($text -split "`n" | Where-Object { $_ })[-1]
        Write-Output ('  {0}: exit {1} after {2:n2} s' -f $how, $result.Status, $took)
        if ($result.Status -ne 130 -or -not $last.Contains('"code":"cancelled"')) { Fail "$how did not cancel: exit $($result.Status) $last" }
        if ($took -gt 2) { Fail "$how took $([math]::Round($took, 2)) s to cancel" }
        if ((Get-FolderNames $folder).Count -ne 0) { Fail "$how left files: $((Get-FolderNames $folder) -join ', ')" }
        if ((Get-Children (Split-Path $folder -Leaf)).Count -ne 0) { Fail "$how left FFmpeg running" }
        $next = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-o', (Join-Path $folder 'video.mp4'), '-q') $media $software
        if ($next.Status -ne 0 -or (Get-FolderNames $folder) -join ',' -ne 'video.mp4') { Fail "the run after a cancel ($how) did not make the video: exit $($next.Status)" }
    }

    Write-Output '== make: an existing output, one held open, and one that appears during the run'
    $folder = New-CleanFolder 'publish'
    $target = Join-Path $folder 'video.mp4'
    $first = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-o', $target, '-j') $media $software
    if ($first.Status -ne 0) { Fail "the first make exited $($first.Status)" }
    $hashBefore = (Get-FileHash $target).Hash
    $refused = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-s', '1:1', '-o', $target, '-j') $media $software
    $lastRefused = @((ConvertTo-Text $refused.Stdout) -split "`n" | Where-Object { $_ })[-1]
    if ($refused.Status -ne 4 -or -not $lastRefused.Contains('"code":"output_exists"')) { Fail "an existing output gave exit $($refused.Status): $lastRefused" }
    if ((Get-FileHash $target).Hash -ne $hashBefore) { Fail 'an existing output was changed without --overwrite' }
    $replaced = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-s', '1:1', '-o', $target, '-w', '-j') $media $software
    $probe = Get-Probe $target
    if ($replaced.Status -ne 0 -or ($probe.streams | Where-Object { $_.codec_type -eq 'video' }).width -ne 480) { Fail "--overwrite did not replace the output: exit $($replaced.Status)" }
    $hashReplaced = (Get-FileHash $target).Hash
    $stream = [System.IO.File]::Open($target, 'Open', 'Read', 'Read')
    try {
        $held = Invoke-Song2Vid @('make', $song3, $scene, '-r', '480p', '-o', $target, '-w', '-j') $media $software
        $lastHeld = @((ConvertTo-Text $held.Stdout) -split "`n" | Where-Object { $_ })[-1]
        Write-Output ('  held open: exit {0} after {1:n1} s' -f $held.Status, $held.Seconds)
        if ($held.Status -ne 4 -or -not $lastHeld.Contains('"code":"output_in_use"')) { Fail "a held output gave exit $($held.Status): $lastHeld" }
    }
    finally { $stream.Dispose() }
    if ((Get-FileHash $target).Hash -ne $hashReplaced) { Fail 'a held output was changed' }
    if (@(Get-FolderNames $folder | Where-Object { $_ -ne 'video.mp4' }).Count -ne 0) { Fail "files were left beside the held output: $((Get-FolderNames $folder) -join ', ')" }
    # A name that appears while the video is being made: without --overwrite it is never touched.
    Remove-Item $target
    $run = Start-Song2Vid @('make', $song3, $scene, '-r', '2160p', '-o', $target, '-j') $media -Environment $software
    $null = Wait-Child $folder @('h264_mf') 60
    [System.IO.File]::WriteAllText($target, 'appeared during the run')
    $late = Wait-Song2Vid $run
    $lastLate = @((ConvertTo-Text $late.Stdout) -split "`n" | Where-Object { $_ })[-1]
    if ($late.Status -ne 4 -or -not $lastLate.Contains('"code":"output_exists"')) { Fail "a name that appeared gave exit $($late.Status): $lastLate" }
    if ([System.IO.File]::ReadAllText($target) -ne 'appeared during the run') { Fail 'a file that appeared during the run was replaced' }
    if (@(Get-FolderNames $folder | Where-Object { $_ -ne 'video.mp4' }).Count -ne 0) { Fail "files were left after the name appeared: $((Get-FolderNames $folder) -join ', ')" }

    Write-Output '== make: a console (a pseudo console, no window): the live line and Ctrl-C'
    Add-Type -TypeDefinition $ptySource
    $folder = New-CleanFolder 'console'
    $commandLine = '"{0}" make "{1}" "{2}" -r 480p -o "{3}"' -f $exe, $song3, $scene, (Join-Path $folder 'live.mp4')
    $pty = [PtyRun]::Start($commandLine, $media)
    $null = $pty.WaitForExit(120000)
    $screen = $pty.Output()
    $statusLive = $pty.ExitCode
    $pty.Dispose()
    Write-Output ('  live: exit {0}, {1} characters of terminal output' -f $statusLive, $screen.Length)
    if ($statusLive -ne 0) { Fail "the run in a console exited $statusLive" }
    foreach ($needle in 'Encoding', [string][char]0x2588, '%', 'elapsed', 'Made live.mp4 (H.264, software encoder).') {
        if (-not $screen.Contains($needle)) { Fail "the console output has no '$needle'" }
    }
    if (-not (Test-Path (Join-Path $folder 'live.mp4'))) { Fail 'the run in a console made no video' }
    $folder = New-CleanFolder 'console-ctrl-c'
    $commandLine = '"{0}" make "{1}" "{2}" -r 2160p -o "{3}"' -f $exe, $song3, $scene, (Join-Path $folder 'live.mp4')
    $pty = [PtyRun]::Start($commandLine, $media)
    $null = Wait-Child $folder @('h264_mf') 60
    Start-Sleep -Milliseconds 500
    $asked = [System.Diagnostics.Stopwatch]::StartNew()
    $pty.Write([string][char]3)
    $exited = $pty.WaitForExit(10000)
    $took = $asked.Elapsed.TotalSeconds
    $screen = $pty.Output()
    $statusC = $pty.ExitCode
    $pty.Dispose()
    Write-Output ('  Ctrl-C: exit {0} after {1:n2} s' -f $statusC, $took)
    if (-not $exited -or $statusC -ne 130) { Fail "Ctrl-C gave exit $statusC" }
    if ($took -gt 2) { Fail "Ctrl-C took $([math]::Round($took, 2)) s" }
    if (-not $screen.Contains('Cancelled.')) { Fail 'Ctrl-C printed no Cancelled. line' }
    if ((Get-FolderNames $folder).Count -ne 0) { Fail "Ctrl-C left files: $((Get-FolderNames $folder) -join ', ')" }
    if ((Get-Children (Split-Path $folder -Leaf)).Count -ne 0) { Fail 'Ctrl-C left FFmpeg running' }
}
else {
    Write-Output 'No three-minute song or scene picture in the bundle: the make speed, kill, cancel, progress and publication checks were not run.'
}

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
