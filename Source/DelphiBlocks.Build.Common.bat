SET _TARGET=%1
IF [%1] == [] (SET _TARGET="Make")

SET _CONFIG=%2
IF [%2] == [] (SET _CONFIG="Debug")

SET _PLATFORM=%3
IF [%3] == [] (SET _PLATFORM="Win32")

SET BUILDTARGET="/t:%_TARGET%"
SET BUILDCONFIG="/p:config=%_CONFIG%"
SET BUILDPLATFORM="/p:platform=%_PLATFORM%"

SET "ERRORCOUNT=0"

@ECHO OFF
msbuild DelphiBlocks.dproj %BUILDTARGET% %BUILDCONFIG% %BUILDPLATFORM% 
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

