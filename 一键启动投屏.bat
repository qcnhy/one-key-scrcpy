@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title scrcpy 一键投屏 · Windows

REM ┌────────────────────────────────────────────────┐
REM │  scrcpy 一键投屏 — Windows 版  v1.1.0          │
REM │  与 macOS「一键启动投屏.command」功能对齐        │
REM ├────────────────────────────────────────────────┤
REM │  • 自动检测已连接的 USB / WiFi 设备             │
REM │  • 记住历史 WiFi IP, 下次直接选                 │
REM │  • 输入数字 = 选序号; 输入 IP 地址 = 直接连      │
REM │  • 自动查找 adb / scrcpy, 无需硬编码路径         │
REM └────────────────────────────────────────────────┘

REM ─── 可调参数 ─────────────────────────────────
set MAX_SIZE=1280
set VIDEO_BIT_RATE=4M
set MAX_FPS=30
set MAX_HISTORY=10

REM ─── 内部路径 (历史文件与 macOS 版同名同格式) ──
set "HISTORY_FILE=%USERPROFILE%\.scrcpy_hosts"
set "TMPF=%TEMP%\scrcpy_onekey.tmp"

REM ═════════════════════════════════════════════
REM  查找工具
REM ═════════════════════════════════════════════
set "SCRCPY="
set "SCRCPY_DIR="
set "ADB="

call :find_tool SCRCPY scrcpy.exe
if defined SCRCPY for %%i in ("!SCRCPY!") do set "SCRCPY_DIR=%%~dpi"
call :find_tool ADB adb.exe

if not defined SCRCPY (
    echo   [错误] 未找到 scrcpy.exe
    echo   安装方式任选其一:
    echo     1. winget install Genymobile.scrcpy
    echo     2. 到 https://github.com/Genymobile/scrcpy 下载 win64 压缩包
    echo        解压到 C:\scrcpy 或本脚本同目录, 均可被自动找到
    goto :fail
)
if not defined ADB (
    echo   [错误] 未找到 adb.exe
    echo   scrcpy win64 压缩包自带 adb.exe, 保持解压目录完整即可
    goto :fail
)

echo.
echo   ==========================================
echo        scrcpy 一键投屏  ·  Windows
echo        WiFi 无线 / USB 有线
echo   ==========================================
echo.

REM ═════════════════════════════════════════════
REM  [1/2] 扫描设备: 已连接的 USB+WiFi, 再补历史 IP
REM ═════════════════════════════════════════════
set /a COUNT=0
set "UNAUTH="
"%ADB%" start-server >nul 2>&1

REM cmd 的 for/f 解析带引号命令易踩坑, 统一经临时文件解析
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

if exist "%HISTORY_FILE%" for /f "usebackq delims=" %%i in ("%HISTORY_FILE%") do (
    if not defined SEEN_%%i (
        set /a COUNT+=1
        set "M_DEV_!COUNT!=%%i"
        set "M_TYPE_!COUNT!=wifi-hist"
    )
)

echo   [步骤 1/2] 选择设备
echo.
if !COUNT! equ 0 (
    echo   （暂无已连接设备, 也无历史记录）
    echo   直接输入 IP 地址即可连接, 例如 192.168.1.100
) else (
    for /l %%i in (1,1,!COUNT!) do (
        if "!M_TYPE_%%i!"=="usb"       echo     %%i. [USB ] !M_DEV_%%i!
        if "!M_TYPE_%%i!"=="wifi-on"   echo     %%i. [WiFi] !M_DEV_%%i! （已连接）
        if "!M_TYPE_%%i!"=="wifi-hist" echo     %%i. [WiFi] !M_DEV_%%i! （历史）
    )
)
if defined UNAUTH echo   （提示: !UNAUTH! 未授权 ADB 调试, 请在手机上允许）
echo.

set "INPUT="
set /p "INPUT=  请输入序号或 IP 地址 （回车取消）: "
if not defined INPUT goto :cancel
set "INPUT=!INPUT: =!"
if not defined INPUT goto :cancel

REM ─── 去前导零 (cmd 把 08 当八进制, 会比较出错) ───
:strip_zero
if "!INPUT:~0,1!"=="0" if not "!INPUT!"=="0" (
    set "INPUT=!INPUT:~1!"
    goto :strip_zero
)

REM ─── 字符门: 只允许 数字 . : , 防特殊字符注入后续命令 ───
set "CHK=!INPUT!"
for %%c in (0 1 2 3 4 5 6 7 8 9) do set "CHK=!CHK:%%c=!"
set "CHK=!CHK:.=!"
set "CHK=!CHK::=!"
if not "!CHK!"=="" (
    echo.
    echo   [错误] 无法识别: '!INPUT!'
    echo   请输入序号 （1, 2 ...） 或 IP 地址 （192.168.x.x）
    goto :fail
)

REM ─── 解析输入: 含 . 或 : → IP; 否则必为纯数字 → 序号 ───
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
        echo   [错误] 序号超出范围: !INPUT!
        if !COUNT! gtr 0 echo   （有效范围 1 - !COUNT!）
        goto :fail
    )
    for %%k in (!INPUT!) do (
        set "TARGET=!M_DEV_%%k!"
        set "ACTION=!M_TYPE_%%k!"
    )
    if not defined TARGET (
        echo.
        echo   [错误] 序号超出范围: !INPUT!
        goto :fail
    )
)

REM ═════════════════════════════════════════════
REM  建立连接
REM ═════════════════════════════════════════════
echo.
if "!ACTION!"=="usb" (
    echo   [USB] 设备就绪: !TARGET!
) else if "!ACTION!"=="wifi-on" (
    echo   设备已连接: !TARGET!
    for /f "delims=:" %%i in ("!TARGET!") do call :save_history "%%i"
    echo   （已记住此 IP, 下次可直接选择）
) else (
    call :wifi_connect "!TARGET!"
    if errorlevel 1 (
        echo.
        echo   [错误] WiFi 连接失败
        echo   请确认:
        echo     · 手机与电脑在同一 WiFi 局域网
        echo     · 手机已开启无线调试 （端口 5555）
        goto :fail
    )
    set "TARGET=!WIFI_TARGET!"
)

REM ═════════════════════════════════════════════
REM  [2/2] 启动 scrcpy
REM ═════════════════════════════════════════════
echo.
echo   [步骤 2/2] 启动 scrcpy 投屏
echo   设备 !TARGET! · 分辨率 %MAX_SIZE% · 码率 %VIDEO_BIT_RATE% · 帧率 %MAX_FPS%
echo   （关闭窗口或按 Ctrl+C 可断开投屏）
echo.
"%SCRCPY%" -s !TARGET! --max-size %MAX_SIZE% --video-bit-rate %VIDEO_BIT_RATE% --max-fps %MAX_FPS% --stay-awake --turn-screen-off
if errorlevel 1 echo   [提示] scrcpy 异常退出, 代码 !errorlevel!
goto :end

REM ═════════════════════════════════════════════
REM  子程序
REM ═════════════════════════════════════════════

:find_tool
REM 用法: call :find_tool 输出变量名 文件名  →  找到则写完整路径, 否则留空
set "FT="
REM 优先 scrcpy 自带目录 (保证 adb 版本与 scrcpy 匹配)
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
REM 5555 是 adb connect 的默认端口, 统一只传纯 IP (与 macOS 版一致)
if "!WC:~-5!"==":5555" set "WC=!WC:~0,-5!"
echo.
echo   连接中 !WC! ...
"%ADB%" connect !WC! > "%TMPF%" 2>&1
for /f "usebackq delims=" %%o in ("%TMPF%") do echo     %%o
REM 首次连接后 adbd 可能要等几秒才从 offline 变为 device, 轮询等待
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
echo   [WiFi] 连接成功
call :save_history "!WC!"
echo   （已记住此 IP, 下次可直接选择）
exit /b 0
:wc_fail
exit /b 1

:save_history
REM 新 IP 置顶写入, 去重, 最多保留 MAX_HISTORY 条
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
echo   已取消
goto :end

:fail
echo.
pause
exit /b 1

:end
echo.
pause
exit /b 0
