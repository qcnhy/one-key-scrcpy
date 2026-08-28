@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title scrcpy One-Key Mirroring - Windows

REM scrcpy one-key launcher for Windows v1.1.0
REM Detect USB/WiFi devices, probe saved addresses, and remember WiFi addresses.
REM Locate adb.exe and scrcpy.exe automatically.

REM Configurable parameters
set MAX_SIZE=1280
set VIDEO_BIT_RATE=4M
set MAX_FPS=30
set MAX_HISTORY=10

REM Internal paths
set "HISTORY_FILE=%~dp0.scrcpy_hosts"
set "TMPF=%TEMP%\scrcpy_onekey.tmp"
set "ONLINE_FILE=%TEMP%\scrcpy_onekey_online.tmp"

REM Find required tools
set "SCRCPY="
set "SCRCPY_DIR="
set "ADB="

call :find_tool SCRCPY scrcpy.exe
if defined SCRCPY for %%i in ("!SCRCPY!") do set "SCRCPY_DIR=%%~dpi"
call :find_tool ADB adb.exe

if not defined SCRCPY (
    echo   [ERROR] scrcpy.exe was not found.
    echo   Install it using either method:
    echo     1. winget install Genymobile.scrcpy
    echo     2. Download the win64 archive from https://github.com/Genymobile/scrcpy
    echo        Extract it to C:\scrcpy or beside this script.
    goto :fail
)
if not defined ADB (
    echo   [ERROR] adb.exe was not found.
    echo   Keep adb.exe from the scrcpy win64 archive beside scrcpy.exe.
    goto :fail
)

echo.
echo   ==========================================
echo        scrcpy One-Key Mirroring - Windows
echo        WiFi wireless / USB wired
echo   ==========================================
echo.

REM Scan connected USB/WiFi devices, then append saved IPs
set /a COUNT=0
set "UNAUTH="
"%ADB%" start-server >nul 2>&1

REM Parse adb output through a temporary file.
"%ADB%" devices > "%TMPF%" 2>nul
for /f "usebackq skip=1 tokens=1,2" %%a in ("%TMPF%") do (
    if "%%b"=="device" (
        set "s=%%a"
        if "!s::=!"=="!s!" (
            set /a COUNT+=1
            set "M_DEV_!COUNT!=%%a"
            set "M_TYPE_!COUNT!=usb"
        ) else (
            set /a COUNT+=1
            set "M_DEV_!COUNT!=%%a"
            set "M_TYPE_!COUNT!=wifi-on"
            for /f "delims=:" %%i in ("!s!") do set "SEEN_%%i=1"
        )
    )
    if "%%b"=="unauthorized" set "UNAUTH=%%a"
)

REM Probe all saved ADB addresses in parallel (one-second overall timeout).
if exist "%HISTORY_FILE%" (
    type nul > "%ONLINE_FILE%"
    where powershell.exe >nul 2>&1
    if not errorlevel 1 powershell.exe -NoProfile -Command "$items=@(); Get-Content -LiteralPath $env:HISTORY_FILE | ForEach-Object { $ip=$_.Trim(); if($ip){ $c=New-Object Net.Sockets.TcpClient; $a=$c.BeginConnect($ip,5555,$null,$null); $items+=New-Object PSObject -Property @{Ip=$ip;Client=$c;Async=$a} } }; foreach($p in $items){ if($p.Async.AsyncWaitHandle.WaitOne(1000)){ try { $p.Client.EndConnect($p.Async); $p.Ip } catch {} }; $p.Client.Close() }" > "%ONLINE_FILE%" 2>nul

    for /f "usebackq delims=" %%i in ("%ONLINE_FILE%") do set "ONLINE_%%i=1"

    REM Add online saved devices first.
    for /f "usebackq delims=" %%i in ("%HISTORY_FILE%") do (
        if not defined SEEN_%%i if defined ONLINE_%%i (
            set /a COUNT+=1
            set "M_DEV_!COUNT!=%%i"
            set "M_TYPE_!COUNT!=wifi-ready"
        )
    )
    REM Then append offline saved devices.
    for /f "usebackq delims=" %%i in ("%HISTORY_FILE%") do (
        if not defined SEEN_%%i if not defined ONLINE_%%i (
            set /a COUNT+=1
            set "M_DEV_!COUNT!=%%i"
            set "M_TYPE_!COUNT!=wifi-hist"
        )
    )
    del /q "%ONLINE_FILE%" >nul 2>&1
)

echo   [Step 1/2] Select a device
echo.
if !COUNT! equ 0 (
    echo   No connected device or saved address was found.
    echo   Enter an IP address directly, for example 192.168.1.100
) else (
    for /l %%i in (1,1,!COUNT!) do (
        if "!M_TYPE_%%i!"=="usb"       echo     %%i. [USB ] !M_DEV_%%i!
        if "!M_TYPE_%%i!"=="wifi-on"   echo     %%i. [WiFi] !M_DEV_%%i! [connected]
        if "!M_TYPE_%%i!"=="wifi-ready" echo     %%i. [WiFi] !M_DEV_%%i! [online]
        if "!M_TYPE_%%i!"=="wifi-hist"  echo     %%i. [WiFi] !M_DEV_%%i! [saved - offline]
    )
)
if defined UNAUTH echo   Note: authorize ADB debugging for !UNAUTH! on the phone.
echo.

set "INPUT="
set /p "INPUT=  Enter a number or IP address [Enter to cancel]: "
if not defined INPUT goto :cancel
set "INPUT=!INPUT: =!"
if not defined INPUT goto :cancel

REM Strip leading zeroes because cmd treats 08 as octal.
:strip_zero
if "!INPUT:~0,1!"=="0" if not "!INPUT!"=="0" (
    set "INPUT=!INPUT:~1!"
    goto :strip_zero
)

REM Allow only digits, dots, and colons.
set "CHK="
for /f "delims=0123456789.:" %%c in ("!INPUT!") do set "CHK=%%c"
if defined CHK (
    echo.
    echo   [ERROR] Invalid input: '!INPUT!'
    echo   Enter a number [1, 2, ...] or an IP address [192.168.x.x].
    goto :fail
)

REM A dot/colon means an address; digits only means a menu index.
set "TARGET="
set "ACTION="
if not "!INPUT:.=!"=="!INPUT!" set "ACTION=wifi-new"
if not "!INPUT::=!"=="!INPUT!" set "ACTION=wifi-new"

if defined ACTION (
    set "TARGET=!INPUT!"
) else (
    set "IDX_OK=1"
    if !INPUT! lss 1 set "IDX_OK=0"
    if !INPUT! gtr !COUNT! set "IDX_OK=0"
    if "!IDX_OK!"=="0" (
        echo.
        echo   [ERROR] Device number is out of range: !INPUT!
        if !COUNT! gtr 0 echo   Valid range: 1 - !COUNT!
        goto :fail
    )
    for %%k in (!INPUT!) do (
        set "TARGET=!M_DEV_%%k!"
        set "ACTION=!M_TYPE_%%k!"
    )
    if not defined TARGET (
        echo.
        echo   [ERROR] Device number is out of range: !INPUT!
        goto :fail
    )
)

REM Establish the selected connection
echo.
if "!ACTION!"=="usb" (
    echo   [USB] Device ready: !TARGET!
) else if "!ACTION!"=="wifi-on" (
    echo   Device already connected: !TARGET!
    for /f "delims=:" %%i in ("!TARGET!") do call :save_history "%%i"
    echo   IP saved for next time.
) else (
    call :wifi_connect "!TARGET!"
    if errorlevel 1 (
        echo.
        echo   [ERROR] WiFi connection failed.
        echo   Check that the phone and PC are on the same WiFi network.
        echo   Check that wireless debugging is enabled on port 5555.
        goto :fail
    )
    set "TARGET=!WIFI_TARGET!"
)

REM Launch scrcpy
echo.
echo   [Step 2/2] Launch scrcpy
echo   Device !TARGET! - Size %MAX_SIZE% - Bitrate %VIDEO_BIT_RATE% - FPS %MAX_FPS%
echo   Close the window or press Ctrl+C to disconnect.
echo.
"%SCRCPY%" -s !TARGET! --max-size %MAX_SIZE% --video-bit-rate %VIDEO_BIT_RATE% --max-fps %MAX_FPS% --stay-awake
set "SCRCPY_EXIT=!errorlevel!"
if not "!ACTION!"=="usb" (
    "%ADB%" disconnect !TARGET! >nul 2>&1
    echo   Wireless ADB disconnected: !TARGET!
)
if not "!SCRCPY_EXIT!"=="0" echo   [NOTICE] scrcpy exited with code !SCRCPY_EXIT!.
goto :end

REM Subroutines

:find_tool
REM Usage: call :find_tool OUTPUT_VARIABLE FILE_NAME
set "FT="
REM Prefer adb shipped beside scrcpy.
if defined SCRCPY_DIR if exist "%SCRCPY_DIR%\%~2" set "FT=%SCRCPY_DIR%\%~2"
if not defined FT (
    where "%~2" >nul 2>&1
    if not errorlevel 1 set "FT=%~2"
)
if not defined FT if exist "%~dp0%~2" set "FT=%~dp0%~2"
if not defined FT for %%d in ("%ProgramFiles%\scrcpy" "%ProgramFiles(x86)%\scrcpy" "%USERPROFILE%\scoop\shims" "%ChocolateyInstall%\bin" "C:\ProgramData\chocolatey\bin") do (
    if not defined FT if exist "%%~d\%~2" set "FT=%%~d\%~2"
)
if not defined FT for /d %%d in ("%SystemDrive%\scrcpy*") do (
    if not defined FT if exist "%%~d\%~2" set "FT=%%~d\%~2"
)
set "%~1=%FT%"
exit /b 0

:wifi_connect
set "WC=%~1"
REM Port 5555 is the default for adb connect.
if "!WC:~-5!"==":5555" set "WC=!WC:~0,-5!"
set "WC_RETRIED=0"
:wc_connect
echo.
echo   Connecting to !WC! ...
"%ADB%" connect !WC! > "%TMPF%" 2>&1
set "CONNECT_STATUS=!errorlevel!"
for /f "usebackq delims=" %%o in ("%TMPF%") do echo     %%o
if not "!CONNECT_STATUS!"=="0" goto :wc_fail
REM Wait for adbd to transition from offline to device.
set "WIFI_TARGET="
set /a TRIES=0
:wc_poll
"%ADB%" devices > "%TMPF%" 2>nul
for /f "usebackq skip=1 tokens=1,2" %%a in ("%TMPF%") do (
    if "%%b"=="device" (
        if "%%a"=="!WC!" set "WIFI_TARGET=%%a"
        if "%%a"=="!WC!:5555" set "WIFI_TARGET=%%a"
    )
)
if defined WIFI_TARGET goto :wc_ok
set /a TRIES+=1
if !TRIES! geq 10 goto :wc_fail
ping -n 2 127.0.0.1 >nul
goto :wc_poll
:wc_ok
echo   [WiFi] Connected successfully.
call :save_history "!WC!"
echo   IP saved for next time.
exit /b 0
:wc_fail
if "!WC_RETRIED!"=="1" exit /b 1
set "WC_RETRIED=1"
echo   ADB state is abnormal. Restarting ADB and retrying...
"%ADB%" kill-server >nul 2>&1
"%ADB%" start-server >nul 2>&1
goto :wc_connect

:save_history
REM Save newest IP first, deduplicate, and limit history size.
set "NEWIP=%~1"
if not defined NEWIP exit /b 0
set "TMPH=%HISTORY_FILE%.tmp"
>"%TMPH%" echo !NEWIP!
set /a HCNT=1
if exist "%HISTORY_FILE%" (
    for /f "usebackq delims=" %%i in ("%HISTORY_FILE%") do (
        if /i not "%%i"=="!NEWIP!" (
            set /a HCNT+=1
            if !HCNT! leq %MAX_HISTORY% >>"%TMPH%" echo %%i
        )
    )
)
move /y "%TMPH%" "%HISTORY_FILE%" >nul 2>&1
exit /b 0

:cancel
echo.
echo   Cancelled.
goto :end

:fail
echo.
pause
exit /b 1

:end
echo.
exit /b 0
