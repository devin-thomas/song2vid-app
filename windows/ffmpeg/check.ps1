param(
    [Parameter(Mandatory)][string] $Staging,
    [Parameter(Mandatory)][string] $Media,
    [string] $SecondStaging,
    [ValidateSet('Titan', 'DeskMini')][string] $Machine = 'Titan'
)

$ErrorActionPreference = 'Stop'
$bin = Join-Path $Staging 'bin/win32-x64'
$ffmpeg = (Resolve-Path (Join-Path $bin 'ffmpeg.exe')).Path
$ffprobe = (Resolve-Path (Join-Path $bin 'ffprobe.exe')).Path
$Media = (Resolve-Path $Media).Path

function Invoke-Native([string] $Program, [string[]] $Arguments) {
    $output = & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$(Split-Path $Program -Leaf) exited $LASTEXITCODE"
    }
    $output
}

$features = @('buildconf', 'encoders', 'decoders', 'demuxers', 'muxers', 'filters', 'protocols', 'bsfs')
$configuration = Invoke-Native $ffmpeg @('-hide_banner', '-buildconf')
if ($configuration -match '^\s*--enable-(gpl|nonfree)\b') {
    throw 'FFmpeg uses GPL or non-free components'
}
$encoders = (Invoke-Native $ffmpeg @('-hide_banner', '-encoders')) -join "`n"
foreach ($encoder in @('h264_nvenc', 'hevc_nvenc', 'h264_mf', 'hevc_mf', 'aac')) {
    if ($encoders -notmatch "(?m)^\s+[AV][A-Z.]+\s+$encoder\s") {
        throw "Missing encoder $encoder"
    }
}
if ($encoders -match '\blibx26[45]\b') { throw 'Unexpected GPL encoder' }
$size = (Get-Item $ffmpeg, $ffprobe | Measure-Object -Property Length -Sum).Sum
Write-Output "LGPL configuration and five required encoders verified. Both programs total $size bytes."

if ($SecondStaging) {
    foreach ($program in @('ffmpeg.exe', 'ffprobe.exe')) {
        $first = (Resolve-Path (Join-Path $bin $program)).Path
        $second = (Resolve-Path (Join-Path $SecondStaging "bin/win32-x64/$program")).Path
        foreach ($feature in $features) {
            $arguments = @('-hide_banner', "-$feature")
            $a = (Invoke-Native $first $arguments) -join "`n"
            $b = (Invoke-Native $second $arguments) -join "`n"
            if ($a -cne $b) { throw "$program differs for -$feature" }
        }
    }
    Write-Output 'Both builds match for configuration and feature lists.'
}

$work = Join-Path $Staging ('qa-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$quiet = @('-hide_banner', '-v', 'error', '-xerror', '-nostdin')
$probe = @('-v', 'error', '-show_streams', '-show_format', '-of', 'json')
try {
    $files = @{
        'still.jpg' = 'mjpeg'; 'still.png' = 'png'; 'still.heic' = 'hevc'; 'tiled.heic' = 'hevc'
        'still.tif' = 'tiff'; 'still.webp' = 'webp'; 'still.gif' = 'gif'; 'still.bmp' = 'bmp'
    }
    foreach ($name in ($files.Keys | Sort-Object)) {
        $inputFile = Join-Path $Media $name
        $inputInfo = Invoke-Native $ffprobe ($probe + $inputFile) | ConvertFrom-Json
        if ($inputInfo.streams[0].codec_name -ne $files[$name]) {
            throw "Unexpected image codec in $name"
        }
        $outputFile = Join-Path $work 'preview.png'
        $arguments = $quiet + @('-y', '-i', $inputFile)
        if ($name -eq 'tiled.heic') {
            $arguments += @('-filter_complex', '[0:g:0]format=rgb24[image]', '-map', '[image]')
        } else {
            $arguments += @('-vf', 'format=rgb24')
        }
        $arguments += @('-frames:v', '1', '-c:v', 'png', '-f', 'image2', '-update', '1', $outputFile)
        Invoke-Native $ffmpeg $arguments
        $image = (Invoke-Native $ffprobe ($probe + $outputFile) | ConvertFrom-Json).streams[0]
        if ($image.codec_name -ne 'png' -or $image.width -ne 320 -or $image.height -ne 240) {
            throw "Unexpected decoded image for $name"
        }
        Write-Output "Decoded $name to a 320x240 PNG."
    }

    $files = @{
        'tone.mp3' = 'mp3'; 'tone.m4a' = 'aac'; 'tone.aac' = 'aac'; 'tone.wav' = 'pcm_s16le'
        'tone.aiff' = 'pcm_s24be'; 'tone.flac' = 'flac'; 'lossless.m4a' = 'alac'; 'tone.caf' = 'pcm_f32le'
    }
    foreach ($name in ($files.Keys | Sort-Object)) {
        $inputFile = Join-Path $Media $name
        $inputInfo = Invoke-Native $ffprobe ($probe + $inputFile) | ConvertFrom-Json
        if ($inputInfo.streams[0].codec_name -ne $files[$name]) {
            throw "Unexpected audio codec in $name"
        }
        $outputFile = Join-Path $work 'audio.mp4'
        Invoke-Native $ffmpeg ($quiet + @('-y', '-i', $inputFile, '-map', '0:a:0', '-c:a', 'aac', '-f', 'mp4', $outputFile))
        $audio = Invoke-Native $ffprobe ($probe + $outputFile) | ConvertFrom-Json
        if ($audio.streams[0].codec_name -ne 'aac' -or [math]::Abs([double]$audio.format.duration - 10) -gt 0.1) {
            throw "Unexpected decoded audio for $name"
        }
        Write-Output "Decoded $name and re-encoded it as AAC."
    }

    $encodersToTest = if ($Machine -eq 'Titan') {
        @('h264_nvenc', 'hevc_nvenc', 'h264_mf')
    } else {
        @('h264_mf', 'hevc_mf')
    }
    foreach ($encoder in $encodersToTest) {
        $outputFile = Join-Path $work "$encoder.mp4"
        $arguments = $quiet + @(
            '-f', 'image2', '-pattern_type', 'none', '-loop', '1', '-framerate', '30', '-i', (Join-Path $Media 'still.png'),
            '-i', (Join-Path $Media 'tone.wav'), '-t', '10', '-vf', 'scale=320:240,pad=352:240:16:0,crop=320:240:16:0',
            '-c:v', $encoder, '-c:a', 'aac'
        )
        if ($encoder.EndsWith('_mf')) {
            $hardware = if ($Machine -eq 'DeskMini') { '1' } else { '0' }
            $arguments += @('-hw_encoding', $hardware, '-pix_fmt', 'nv12')
        } else {
            $arguments += @('-pix_fmt', 'yuv420p')
        }
        $codec, $tag = if ($encoder.StartsWith('hevc_')) { 'hevc', 'hvc1' } else { 'h264', 'avc1' }
        Invoke-Native $ffmpeg ($arguments + @('-tag:v', $tag, '-movflags', '+faststart', '-f', 'mp4', $outputFile))
        $result = Invoke-Native $ffprobe ($probe + $outputFile) | ConvertFrom-Json
        $video = $result.streams[0]
        if ($video.codec_name -ne $codec -or $video.codec_tag_string -ne $tag -or
            $video.width -ne 320 -or $video.height -ne 240 -or [int]$video.nb_frames -ne 300 -or
            $result.streams[1].codec_name -ne 'aac' -or [math]::Abs([double]$result.format.duration - 10) -gt 0.1) {
            throw "Unexpected encode result for $encoder"
        }
        Write-Output "$encoder encoded 300 frames and AAC in a $($result.format.duration) second MP4."
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
