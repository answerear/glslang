@echo off
setlocal EnableDelayedExpansion

pushd "%~dp0"

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "BUILD_DIR=%SCRIPT_DIR%\build_vs2019_x64"
set "STAGE_DIR=%BUILD_DIR%\install"
for %%I in ("%SCRIPT_DIR%\..\..\Tiny3D\dependencies\glslang") do set "TARGET_DIR=%%~fI"

set "TARGET_INC_DIR=%TARGET_DIR%\include"
set "TARGET_LIB_DEBUG_DIR=%TARGET_DIR%\prebuilt\Windows\x64\Debug"
set "TARGET_LIB_RELEASE_DIR=%TARGET_DIR%\prebuilt\Windows\x64\Release"

set "GLSLANG_LIBS=glslang glslang-default-resource-limits MachineIndependent GenericCodeGen OSDependent SPIRV SPIRV-Tools SPIRV-Tools-opt"

set "MI_HEADERS=attribute.h gl_types.h Initialize.h iomapper.h LiveTraverser.h localintermediate.h ParseHelper.h parseVersions.h propagateNoContraction.h reflection.h Scan.h ScanContext.h span.h SymbolTable.h Versions.h"

echo ============================================================================
echo [1/6] Checking required tools and preparing External dependencies...
echo ============================================================================
where python >nul 2>nul
if errorlevel 1 (
    echo [ERROR] python not found in PATH! Python 3.x is required to fetch external sources and build SPIRV-Tools.
    goto :error
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] git not found in PATH! Git is required to checkout external dependencies.
    goto :error
)

where cmake >nul 2>nul
if errorlevel 1 (
    echo [ERROR] cmake not found in PATH! CMake ^>= 3.22.1 is required.
    goto :error
)

echo Fetching/updating external dependencies via update_glslang_sources.py...
python "%SCRIPT_DIR%\update_glslang_sources.py"
if errorlevel 1 (
    echo [ERROR] Failed to prepare external dependencies via update_glslang_sources.py!
    goto :error
)

if not exist "%SCRIPT_DIR%\External\spirv-tools\CMakeLists.txt" (
    echo [ERROR] External\spirv-tools\CMakeLists.txt not found after running update_glslang_sources.py!
    goto :error
)
if not exist "%SCRIPT_DIR%\External\spirv-tools\external\spirv-headers\CMakeLists.txt" (
    echo [ERROR] External\spirv-tools\external\spirv-headers\CMakeLists.txt not found!
    goto :error
)

echo.
echo ============================================================================
echo [2/6] Cleaning previous build directory "%BUILD_DIR%"...
echo ============================================================================
if exist "%BUILD_DIR%" (
    rmdir /S /Q "%BUILD_DIR%"
    if exist "%BUILD_DIR%" (
        echo [ERROR] Failed to clean "%BUILD_DIR%". Please close any open files/IDE and retry.
        goto :error
    )
    echo Previous build directory cleaned.
) else (
    echo No previous build directory found.
)

echo.
echo ============================================================================
echo [3/6] Configuring glslang with CMake (Visual Studio 16 2019, x64)...
echo ============================================================================
cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" ^
    -G "Visual Studio 16 2019" ^
    -A x64 ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DBUILD_EXTERNAL=ON ^
    -DENABLE_OPT=ON ^
    -DENABLE_SPIRV=ON ^
    -DENABLE_HLSL=ON ^
    -DGLSLANG_TESTS=OFF ^
    -DENABLE_GLSLANG_BINARIES=OFF ^
    -DGLSLANG_ENABLE_INSTALL=ON ^
    -DCMAKE_INSTALL_PREFIX="%STAGE_DIR%"
if errorlevel 1 (
    echo [ERROR] CMake configure failed!
    goto :error
)

echo.
echo ============================================================================
echo [4/6] Building and staging glslang [Debug x64]...
echo ============================================================================
cmake --build "%BUILD_DIR%" --config Debug --target install --parallel
if errorlevel 1 (
    echo [ERROR] CMake Debug build/install failed!
    goto :error
)

echo.
echo ============================================================================
echo [5/6] Building and staging glslang [Release x64]...
echo ============================================================================
cmake --build "%BUILD_DIR%" --config Release --target install --parallel
if errorlevel 1 (
    echo [ERROR] CMake Release build/install failed!
    goto :error
)

echo.
echo ============================================================================
echo [6/6] Synchronizing headers and libraries to "%TARGET_DIR%"...
echo ============================================================================
if not exist "%TARGET_INC_DIR%\glslang\Include"            mkdir "%TARGET_INC_DIR%\glslang\Include"
if not exist "%TARGET_INC_DIR%\glslang\MachineIndependent" mkdir "%TARGET_INC_DIR%\glslang\MachineIndependent"
if not exist "%TARGET_INC_DIR%\glslang\Public"             mkdir "%TARGET_INC_DIR%\glslang\Public"
if not exist "%TARGET_INC_DIR%\SPIRV"                      mkdir "%TARGET_INC_DIR%\SPIRV"
if not exist "%TARGET_LIB_DEBUG_DIR%"                      mkdir "%TARGET_LIB_DEBUG_DIR%"
if not exist "%TARGET_LIB_RELEASE_DIR%"                    mkdir "%TARGET_LIB_RELEASE_DIR%"

:: 1. Copy Debug & Release static libraries (8 libs each)
for %%L in (%GLSLANG_LIBS%) do (
    if not exist "%STAGE_DIR%\lib\%%Ld.lib" (
        echo [ERROR] Missing expected Debug library: "%STAGE_DIR%\lib\%%Ld.lib"
        goto :error
    )
    copy /Y "%STAGE_DIR%\lib\%%Ld.lib" "%TARGET_LIB_DEBUG_DIR%\%%Ld.lib" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy "%%Ld.lib" to "%TARGET_LIB_DEBUG_DIR%"
        goto :error
    )

    if not exist "%STAGE_DIR%\lib\%%L.lib" (
        echo [ERROR] Missing expected Release library: "%STAGE_DIR%\lib\%%L.lib"
        goto :error
    )
    copy /Y "%STAGE_DIR%\lib\%%L.lib" "%TARGET_LIB_RELEASE_DIR%\%%L.lib" >nul
    if errorlevel 1 (
        echo [ERROR] Failed to copy "%%L.lib" to "%TARGET_LIB_RELEASE_DIR%"
        goto :error
    )
)

:: 2. Copy top-level glslang headers (build_info.h + glsl_intrinsic_header.h)
copy /Y "%BUILD_DIR%\include\glslang\build_info.h"   "%TARGET_INC_DIR%\glslang\build_info.h" >nul
if errorlevel 1 goto :copy_header_error

copy /Y "%SCRIPT_DIR%\glslang\glsl_intrinsic_header.h" "%TARGET_INC_DIR%\glslang\glsl_intrinsic_header.h" >nul
if errorlevel 1 goto :copy_header_error

:: 3. Copy glslang/Public/*.h
xcopy /Y /Q "%SCRIPT_DIR%\glslang\Public\*.h" "%TARGET_INC_DIR%\glslang\Public\" >nul
if errorlevel 1 goto :copy_header_error

:: 4. Copy glslang/Include/*.h
xcopy /Y /Q "%SCRIPT_DIR%\glslang\Include\*.h" "%TARGET_INC_DIR%\glslang\Include\" >nul
if errorlevel 1 goto :copy_header_error

:: 5. Copy glslang/MachineIndependent headers (matching existing dependencies/glslang structure)
for %%H in (%MI_HEADERS%) do (
    copy /Y "%SCRIPT_DIR%\glslang\MachineIndependent\%%H" "%TARGET_INC_DIR%\glslang\MachineIndependent\%%H" >nul
    if errorlevel 1 goto :copy_header_error
)

:: 6. Copy SPIRV/*.h and SPIRV/*.hpp11 to include/SPIRV/
xcopy /Y /Q "%SCRIPT_DIR%\SPIRV\*.h"     "%TARGET_INC_DIR%\SPIRV\" >nul
if errorlevel 1 goto :copy_header_error

xcopy /Y /Q "%SCRIPT_DIR%\SPIRV\*.hpp11" "%TARGET_INC_DIR%\SPIRV\" >nul
if errorlevel 1 goto :copy_header_error

echo.
echo ============================================================================
echo [SUCCESS] glslang Windows x64 (Debug ^& Release) build and sync completed!
echo   Headers     : %TARGET_INC_DIR%
echo   Debug Libs  : %TARGET_LIB_DEBUG_DIR% (8 libs)
echo   Release Libs: %TARGET_LIB_RELEASE_DIR% (8 libs)
echo ============================================================================
popd
endlocal
pause
exit /b 0

:copy_header_error
echo [ERROR] Failed to copy header files to "%TARGET_INC_DIR%"!

:error
echo.
echo ============================================================================
echo [FAILED] Build or synchronization aborted due to errors above!
echo ============================================================================
popd
endlocal
pause
exit /b 1
