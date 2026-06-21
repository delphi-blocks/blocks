@ECHO OFF

:: Delphi 13.0 Florence
set "BDSVER=37.0"

for /f "tokens=2,*" %%A in (
    'reg query "HKCU\SOFTWARE\Embarcadero\BDS\%BDSVER%" /v RootDir 2^>nul'
) do set "BDS=%%B"

if not defined BDS (
    echo ERROR: RAD Studio %BDSVER% not found in the registry.
    exit /b 1
)

REM remove any trailing backslash
if "%BDS:~-1%"=="\" set "BDS=%BDS:~0,-1%"

CALL "%BDS%\bin\rsvars.bat"
::::::::::::::::::::::::::::::::

:: Set Target, config and platform
SET _TARGET=%1
IF [%1] == [] (SET _TARGET="Make")

SET _CONFIG=%2
IF [%2] == [] (SET _CONFIG="Release")

SET _PLATFORM=%3
IF [%3] == [] (SET _PLATFORM="Win32")

SET BUILDTARGET="/t:%_TARGET%"
SET BUILDCONFIG="/p:config=%_CONFIG%"
SET BUILDPLATFORM="/p:platform=%_PLATFORM%"
SET EXEOUTPUT="/p:DCC_ExeOutput=..\\setup\\%_PLATFORM%"

:: Platform name without quotes, used to build output paths below
SET "PLATFORMDIR=%_PLATFORM:"=%"

:: Script used to sign executables; called only if it exists
SET "SIGNSCRIPT=%~dp0SignFile.bat"

SET "ERRORCOUNT=0"

@ECHO OFF
:: Build BLOCKS.EXE
msbuild ..\Source\Blocks.dproj /t:Rebuild %BUILDTARGET% %BUILDCONFIG% %BUILDPLATFORM% %EXEOUTPUT%
IF %ERRORLEVEL% NEQ 0 (
  set /a ERRORCOUNT+=1
) ELSE (
  IF EXIST "%SIGNSCRIPT%" CALL "%SIGNSCRIPT%" "%~dp0%PLATFORMDIR%\Blocks.exe"
)

:: Build LAUNCHER.EXE
msbuild ..\Source\Launcher.dproj /t:Rebuild %BUILDTARGET% %BUILDCONFIG% %BUILDPLATFORM% %EXEOUTPUT%
IF %ERRORLEVEL% NEQ 0 (
  set /a ERRORCOUNT+=1
) ELSE (
  IF EXIST "%SIGNSCRIPT%" CALL "%SIGNSCRIPT%" "%~dp0%PLATFORMDIR%\Launcher.exe"
)


IF %ERRORCOUNT% NEQ 0 (
  
  ECHO ========================================================
  ECHO ===    %ERRORCOUNT% DelphiBlocks Failed to Compile   ===
  ECHO ===========================================  ============
  EXIT /B 1
  
) ELSE ( 

  ECHO =============================================
  ECHO ===    DelphiBlocks Compiled Successful   ===
  ECHO =============================================
  
)    

::::::::::::::::::::::::::::::::::::::::::::::::::
:: Build setup with InnoSetup
::::::::::::::::::::::::::::::::::::::::::::::::::

ECHO "Build setup.exe"

@echo off

:: Find InnoSetup path on windows registry
for /f "tokens=2*" %%a in ('reg query "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1" /v "InstallLocation" 2^>nul') do (
    set "INNO_PATH=%%b"
)

:: Check if exists
if not defined INNO_PATH (
    echo Inno Setup non found in windows registry
    exit /b 1
)

:: Strip final slash
if "%INNO_PATH:~-1%"=="\" set "INNO_PATH=%INNO_PATH:~0,-1%"

:: Run InnoSetup compiler
"%INNO_PATH%\ISCC.exe" blocks.iss /DPlatform=%_PLATFORM%
IF %ERRORLEVEL% NEQ 0 EXIT /B 1

:: Find the installer just produced (most recently modified .exe in Output) and sign it
IF EXIST "%SIGNSCRIPT%" (
  SET "SETUPSIGNED="
  FOR /F "delims=" %%F IN ('dir /b /o-d "%~dp0Output\*.exe"') DO (
    IF NOT DEFINED SETUPSIGNED (
      SET "SETUPSIGNED=1"
      CALL "%SIGNSCRIPT%" "%~dp0Output\%%F"
    )
  )
)