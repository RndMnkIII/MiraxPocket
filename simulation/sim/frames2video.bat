@echo off
REM ==========================================================================
REM  frames2video.bat  -  Turn a numbered frame sequence into a video (Windows)
REM  Needs ffmpeg on PATH (https://www.gyan.dev/ffmpeg/builds/  ->  add /bin).
REM
REM  Usage (cmd.exe or PowerShell):
REM    frames2video.bat [indir] [fps] [scale] [out] [rot] [ext] [aud] [arate] [ach]
REM      indir  frame folder             (default: frames)
REM      fps    input frame rate          (default: 60  -> arcade native)
REM      scale  integer pixel upscale     (default: 3   -> 256x240 => 768x720)
REM      out    output file               (default: mirax.mp4)
REM      rot    0 | 90 | 180 | 270        (default: 0   -> no rotation)
REM             Mirax is a vertical (ROT90) game; use 90 to view upright.
REM      ext    ppm | png                 (default: ppm -> ffmpeg reads PPM directly)
REM      aud    audio file from the sim   (default: mirax.wav)
REM             .wav -> read directly (rate/channels taken from header)
REM             .pcm / .raw -> signed 16-bit little-endian; give arate/ach below
REM             set to "none" to force a silent video
REM      arate  sample rate for RAW PCM   (default: 48000) - ignored for .wav
REM      ach    channels for RAW PCM      (default: 1 = mono) - ignored for .wav
REM
REM  Examples:
REM    frames2video.bat
REM    frames2video.bat frames 60 3 mirax.mp4 90
REM    frames2video.bat frames 60 4 mirax_stage1.mp4 90 png mirax.wav
REM    frames2video.bat frames 60 3 mirax.mp4 90 ppm sound.pcm 48000 1
REM ==========================================================================
setlocal
set INDIR=%~1
if "%INDIR%"=="" set INDIR=frames
set FPS=%~2
if "%FPS%"=="" set FPS=60
set SCALE=%~3
if "%SCALE%"=="" set SCALE=3
set OUT=%~4
if "%OUT%"=="" set OUT=mirax.mp4
set ROT=%~5
if "%ROT%"=="" set ROT=0
set EXT=%~6
if "%EXT%"=="" set EXT=ppm
set AUD=%~7
if "%AUD%"=="" set AUD=mirax.wav
set ARATE=%~8
if "%ARATE%"=="" set ARATE=48000
set ACH=%~9
if "%ACH%"=="" set ACH=1

REM --- build the rotation part of the filter chain ---
set ROTF=
if "%ROT%"=="90"  set ROTF=,transpose=1
if "%ROT%"=="180" set ROTF=,transpose=1,transpose=1
if "%ROT%"=="270" set ROTF=,transpose=2

REM --- decide the audio input / codec args ------------------------------------
REM  AIN  = ffmpeg input args for the audio (empty => no audio)
REM  ACODEC = output audio codec args (empty => no audio)
set AIN=
set ACODEC=
if /I "%AUD%"=="none" goto audio_done
if not exist "%AUD%" (
  echo [i] No audio file "%AUD%" found - encoding a SILENT video.
  goto audio_done
)
REM  .wav -> let ffmpeg parse the header; anything else -> raw signed 16-bit LE
if /I "%AUD:~-4%"==".wav" (
  set AIN=-i "%AUD%"
  echo [i] Muxing WAV audio: %AUD%
) else (
  set AIN=-f s16le -ar %ARATE% -ac %ACH% -i "%AUD%"
  echo [i] Muxing RAW PCM audio: %AUD%  ^(s16le, %ARATE% Hz, %ACH% ch^)
)
REM  AAC in mp4 = universally playable; -shortest trims to the shorter stream
set ACODEC=-c:a aac -b:a 192k -ac 2 -shortest
:audio_done

echo Encoding %INDIR%\frame_%%05d.%EXT%  ->  %OUT%   (fps=%FPS% scale=%SCALE% rot=%ROT%)

ffmpeg -y -framerate %FPS% -i "%INDIR%\frame_%%05d.%EXT%" %AIN% ^
  -vf "scale=iw*%SCALE%:ih*%SCALE%:flags=neighbor%ROTF%" ^
  -c:v libx264 -pix_fmt yuv420p -crf 18 %ACODEC% -movflags +faststart "%OUT%"

if errorlevel 1 (
  echo.
  echo ffmpeg failed. Check that ffmpeg is on PATH and the frames exist.
  exit /b 1
)
echo Done: %OUT%
endlocal
