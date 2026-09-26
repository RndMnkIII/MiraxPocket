@echo off
REM ============================================================================
REM  pack.bat - Empaqueta el core "Mirax" para Analogue Pocket tras compilar
REM  en Quartus. Invierte los bits de cada byte del .rbf (bitstream.rbf_r) y
REM  arma en release\ la estructura lista para copiar a la raiz de la SD:
REM
REM     release\
REM       Cores\<AUTHOR>.<SHORTNAME>\   bitstream.rbf_r + *.json + info.txt + icon.bin
REM       Assets\ ...                   (copiado de dist\Assets)
REM       Platforms\ ...                (copiado de dist\Platforms)
REM       Presets\ ...                  (copiado de dist\Presets)
REM       <cualquier otra cosa en dist\>
REM
REM  y genera <AUTHOR>.<SHORTNAME>_<version>.zip con todo el contenido de release\.
REM
REM  Uso:   pack.bat [ruta\al\fichero.rbf]
REM         (si se omite, se usa el .rbf mas reciente de src\fpga\output_files)
REM ============================================================================
setlocal enableextensions enabledelayedexpansion

REM ---- Datos del core (edita si cambias autor/nombre/plataforma) -------------
set "AUTHOR=RndMnkIII"
set "SHORTNAME=MiraxPocket"
set "PLATFORM=mirax"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "DIST=%ROOT%\dist"
set "COREID=%AUTHOR%.%SHORTNAME%"
set "OUTDIR=%ROOT%\release"
set "COREDIR=%OUTDIR%\Cores\%COREID%"

REM Version leida de core.json (para el nombre del zip); "dev" si no se encuentra
set "VERSION="
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "try{(Get-Content -Raw '%ROOT%\core.json' | ConvertFrom-Json).core.metadata.version}catch{}"`) do set "VERSION=%%V"
if "%VERSION%"=="" set "VERSION=dev"

REM ---- 1) Localizar el .rbf compilado ---------------------------------------
set "RBF=%~1"
if "%RBF%"=="" (
  for /f "delims=" %%F in ('dir /b /o-d "%ROOT%\src\fpga\output_files\*.rbf" 2^>nul') do (
    if not defined RBF set "RBF=%ROOT%\src\fpga\output_files\%%F"
  )
)
if "%RBF%"=="" (
  echo ERROR: no encuentro el .rbf. Compila en Quartus o pasa la ruta:
  echo        pack.bat src\fpga\output_files\ap_core.rbf
  exit /b 1
)
if not exist "%RBF%"  ( echo ERROR: no existe "%RBF%" & exit /b 1 )
if not exist "%DIST%\" ( echo ERROR: no existe la carpeta dist\ & exit /b 1 )
echo RBF de entrada : %RBF%
echo Version        : %VERSION%

REM ---- 2) Preparar release\ y copiar TODO dist\ -----------------------------
if exist "%OUTDIR%" rmdir /s /q "%OUTDIR%"
mkdir "%OUTDIR%" >nul 2>&1
REM /E incluye subcarpetas (tambien vacias), /H ficheros ocultos
xcopy "%DIST%\*" "%OUTDIR%\" /E /I /H /Y /Q >nul
if errorlevel 1 ( echo ERROR: fallo copiando dist\ & exit /b 1 )
REM icon.bin va dentro de la carpeta del core, no en la raiz
if exist "%OUTDIR%\icon.bin" del /q "%OUTDIR%\icon.bin"
REM Quitar ficheros marcador de git; las carpetas vacias se mantienen
del /s /q /a "%OUTDIR%\.gitkeep" >nul 2>&1
del /s /q /a "%OUTDIR%\.keep"    >nul 2>&1

REM ---- 3) Crear carpetas del core y de assets -------------------------------
if not exist "%COREDIR%"                        mkdir "%COREDIR%"
if not exist "%OUTDIR%\Platforms\_images"       mkdir "%OUTDIR%\Platforms\_images"
if not exist "%OUTDIR%\Assets\%PLATFORM%\common" mkdir "%OUTDIR%\Assets\%PLATFORM%\common"
if not exist "%OUTDIR%\Assets\%PLATFORM%\%COREID%" mkdir "%OUTDIR%\Assets\%PLATFORM%\%COREID%"

REM ---- 4) Invertir los bits de cada byte  ->  bitstream.rbf_r ---------------
set "REV=%COREDIR%\bitstream.rbf_r"
echo Invirtiendo bits -^> bitstream.rbf_r ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$b=[IO.File]::ReadAllBytes('%RBF%'); $l=New-Object 'byte[]' 256; for($i=0;$i-lt256;$i++){$r=0;for($j=0;$j-lt8;$j++){if($i-band(1-shl$j)){$r=$r-bor(1-shl(7-$j))}};$l[$i]=[byte]$r}; $o=New-Object 'byte[]' $b.Length; for($k=0;$k-lt$b.Length;$k++){$o[$k]=$l[$b[$k]]}; [IO.File]::WriteAllBytes('%REV%',$o)"
if errorlevel 1 ( echo ERROR: fallo la inversion de bits en PowerShell & exit /b 1 )

REM ---- 5) Copiar definiciones del core (JSON + info + icono) ----------------
for %%J in (core.json video.json audio.json data.json input.json interact.json variants.json info.txt) do (
  if exist "%ROOT%\%%J" ( copy /y "%ROOT%\%%J" "%COREDIR%\" >nul ) else ( echo AVISO: falta %%J )
)
if exist "%DIST%\icon.bin" ( copy /y "%DIST%\icon.bin" "%COREDIR%\icon.bin" >nul ) else ( echo AVISO: falta dist\icon.bin )

REM ---- 6) Comprobaciones minimas --------------------------------------------
if not exist "%OUTDIR%\Platforms\%PLATFORM%.json"        echo AVISO: falta Platforms\%PLATFORM%.json en dist\
if not exist "%OUTDIR%\Platforms\_images\%PLATFORM%.bin" echo AVISO: falta Platforms\_images\%PLATFORM%.bin en dist\

REM ---- 7) Comprimir todo release\ -------------------------------------------
REM ZipFile.CreateFromDirectory conserva las carpetas vacias (Compress-Archive no)
set "ZIP=%ROOT%\%COREID%_%VERSION%.zip"
if exist "%ZIP%" del /q "%ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::CreateFromDirectory('%OUTDIR%','%ZIP%',[IO.Compression.CompressionLevel]::Optimal,$false)"
if errorlevel 1 ( echo ERROR: fallo al crear el ZIP & exit /b 1 )

echo -----------------------------------------------------------------
echo OK. bitstream.rbf_r generado en:
echo   %REV%
echo Estructura   : %OUTDIR%
tree /f /a "%OUTDIR%"
echo ZIP distrib. : %ZIP%  (descomprimir en la raiz de la SD del Pocket)
echo -----------------------------------------------------------------
endlocal
