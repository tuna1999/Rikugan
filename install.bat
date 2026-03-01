@echo off
setlocal enabledelayedexpansion

:: Iris installer for Windows
:: Usage: install.bat [IDA_USER_DIR]
::   IDA_USER_DIR  Optional path to IDA user directory (default: auto-detect)

set "SCRIPT_DIR=%~dp0"
:: Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

:: ── Sanity checks ────────────────────────────────────────────────────

if not exist "%SCRIPT_DIR%\iris_plugin.py" (
    echo [-] iris_plugin.py not found in %SCRIPT_DIR% — run this from the repo root
    exit /b 1
)

if not exist "%SCRIPT_DIR%\iris\" (
    echo [-] iris\ package not found in %SCRIPT_DIR% — run this from the repo root
    exit /b 1
)

:: ── Locate IDA user directory ────────────────────────────────────────

set "IDA_USER_DIR="

if not "%~1"=="" (
    if exist "%~1\" (
        set "IDA_USER_DIR=%~1"
        echo [*] Using provided IDA directory: !IDA_USER_DIR!
    ) else (
        echo [-] Provided IDA directory does not exist: %~1
        exit /b 1
    )
)

if not defined IDA_USER_DIR (
    :: Try common Windows IDA locations
    if exist "%APPDATA%\Hex-Rays\IDA Pro\" (
        set "IDA_USER_DIR=%APPDATA%\Hex-Rays\IDA Pro"
        echo [*] Auto-detected IDA directory: !IDA_USER_DIR!
    ) else if exist "%USERPROFILE%\.idapro\" (
        set "IDA_USER_DIR=%USERPROFILE%\.idapro"
        echo [*] Auto-detected IDA directory: !IDA_USER_DIR!
    ) else if exist "%IDAUSR%\" (
        set "IDA_USER_DIR=%IDAUSR%"
        echo [*] Auto-detected IDA directory via IDAUSR: !IDA_USER_DIR!
    ) else (
        set "IDA_USER_DIR=%APPDATA%\Hex-Rays\IDA Pro"
        echo [!] No IDA directory found, defaulting to !IDA_USER_DIR!
    )
)

set "PLUGINS_DIR=%IDA_USER_DIR%\plugins"
set "CONFIG_DIR=%IDA_USER_DIR%\iris"

:: ── Install dependencies ─────────────────────────────────────────────

echo [*] Installing Python dependencies...
where pip3 >nul 2>&1
if !errorlevel! equ 0 (
    pip3 install -r "%SCRIPT_DIR%\requirements.txt" --quiet 2>nul
    if !errorlevel! neq 0 (
        echo [!] pip3 install failed — you may need to install dependencies manually
    )
) else (
    where pip >nul 2>&1
    if !errorlevel! equ 0 (
        pip install -r "%SCRIPT_DIR%\requirements.txt" --quiet 2>nul
        if !errorlevel! neq 0 (
            echo [!] pip install failed — you may need to install dependencies manually
        )
    ) else (
        echo [!] pip not found — install dependencies manually: pip install -r requirements.txt
    )
)

:: ── Create directories ───────────────────────────────────────────────

if not exist "%PLUGINS_DIR%\" mkdir "%PLUGINS_DIR%"
if not exist "%CONFIG_DIR%\"  mkdir "%CONFIG_DIR%"

:: ── Copy built-in skills ────────────────────────────────────────────

set "SKILLS_DIR=%CONFIG_DIR%\skills"
set "BUILTINS_SRC=%SCRIPT_DIR%\iris\skills\builtins"

if exist "%BUILTINS_SRC%\" (
    echo [*] Installing built-in skills into %SKILLS_DIR%...
    if not exist "%SKILLS_DIR%\" mkdir "%SKILLS_DIR%"
    for /d %%S in ("%BUILTINS_SRC%\*") do (
        set "SLUG=%%~nxS"
        if exist "%SKILLS_DIR%\!SLUG!\" (
            echo [+] /!SLUG! already exists, skipping ^(user copy preserved^)
        ) else (
            xcopy "%%S" "%SKILLS_DIR%\!SLUG!\" /E /I /Y /Q >nul
            echo [+] /!SLUG!
        )
    )
) else (
    echo [!] Built-in skills not found at %BUILTINS_SRC%, skipping
)

:: ── Install plugin (copy) ────────────────────────────────────────────

echo [*] Installing Iris into %PLUGINS_DIR%...

:: iris_plugin.py
if exist "%PLUGINS_DIR%\iris_plugin.py" (
    del "%PLUGINS_DIR%\iris_plugin.py"
)
copy "%SCRIPT_DIR%\iris_plugin.py" "%PLUGINS_DIR%\iris_plugin.py" >nul
if !errorlevel! equ 0 (
    echo [+] iris_plugin.py -^> %PLUGINS_DIR%\iris_plugin.py
) else (
    echo [-] Failed to copy iris_plugin.py
    exit /b 1
)

:: iris/ package — use directory junction (symlink-like, no admin required)
if exist "%PLUGINS_DIR%\iris\" (
    :: Check if it's a junction
    fsutil reparsepoint query "%PLUGINS_DIR%\iris" >nul 2>&1
    if !errorlevel! equ 0 (
        rmdir "%PLUGINS_DIR%\iris"
    ) else (
        :: Real directory — back it up
        echo [!] Backing up existing iris\ to iris.bak\
        if exist "%PLUGINS_DIR%\iris.bak\" rmdir /s /q "%PLUGINS_DIR%\iris.bak"
        ren "%PLUGINS_DIR%\iris" "iris.bak"
    )
)

mklink /J "%PLUGINS_DIR%\iris" "%SCRIPT_DIR%\iris" >nul 2>&1
if !errorlevel! equ 0 (
    echo [+] iris\ -^> %PLUGINS_DIR%\iris  (junction)
) else (
    :: Junction failed (rare), fall back to xcopy
    echo [!] Junction failed, falling back to copy...
    xcopy "%SCRIPT_DIR%\iris" "%PLUGINS_DIR%\iris\" /E /I /Y /Q >nul
    if !errorlevel! equ 0 (
        echo [+] iris\ -^> %PLUGINS_DIR%\iris  (copied)
    ) else (
        echo [-] Failed to copy iris\ package
        exit /b 1
    )
)

:: ── Done ─────────────────────────────────────────────────────────────

echo.
echo [+] Iris installed successfully!
echo [*] Plugin:  %PLUGINS_DIR%\iris_plugin.py
echo [*] Package: %PLUGINS_DIR%\iris
echo [*] Config:  %CONFIG_DIR%\
echo [*] Skills:  %SKILLS_DIR%\
echo.
echo [*] Open IDA and press Ctrl+Shift+I to start Iris.
echo [*] First run: click Settings to configure your LLM provider and API key.

endlocal
