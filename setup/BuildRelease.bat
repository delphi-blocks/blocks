@ECHO OFF

:: Delphi 13.0 Florence
@SET BDS=C:\Program Files (x86)\Embarcadero\Studio\37.0
@SET BDSINCLUDE=%BDS%\include
@SET BDSCOMMONDIR=C:\Users\Public\Documents\Embarcadero\Studio\37.0
@SET FrameworkDir=C:\Windows\Microsoft.NET\Framework\v4.0.30319
@SET FrameworkVersion=v4.5
@SET FrameworkSDKDir=
@SET PATH=%FrameworkDir%;%FrameworkSDKDir%;%BDS%\bin;%BDS%\bin64;%PATH%
@SET LANGDIR=EN
@SET PLATFORM=
@SET PlatformSDK=
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

SET "ERRORCOUNT=0"

@ECHO OFF
:: Build BLOCKS.EXE
msbuild ..\Source\Blocks.dproj %BUILDTARGET% %BUILDCONFIG% %BUILDPLATFORM% 
IF %ERRORLEVEL% NEQ 0 set /a ERRORCOUNT+=1

:: Build LAUNCHER.EXE
msbuild ..\Source\Launcher.dproj %BUILDTARGET% %BUILDCONFIG% %BUILDPLATFORM% 
IF %ERRORLEVEL% NEQ 0 set /a ERRORCOUNT+=1


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
"%INNO_PATH%\ISCC.exe" blocks.iss