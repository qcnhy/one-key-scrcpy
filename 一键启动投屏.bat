@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title MI6 无头模式 - scrcpy 投屏

set ADB=C:\scrcpy-win64-v3.3.4\adb.exe
set SCRCPY=C:\scrcpy-win64-v3.3.4\scrcpy.exe
set WIFI_IP=192.168.x.x:5555
set USB_DEV=你的设备序列号
set DEV=

echo ============================================
echo   MI6 无头模式 - scrcpy 一键投屏
echo   连接方式: WiFi无线 / USB有线
echo ============================================
echo.

echo [1/2] 连接设备...

REM --- WiFi ---
"%ADB%" connect %WIFI_IP% >nul 2>&1
"%ADB%" devices | findstr "%WIFI_IP%.*device" >nul 2>&1
if not errorlevel 1 (
    set DEV=%WIFI_IP%
    echo   [WiFi] 连接成功  %WIFI_IP%
    goto :launch
)
echo   WiFi不可用，尝试USB...

REM --- USB ---
"%ADB%" devices | findstr "%USB_DEV%.*device" >nul 2>&1
if not errorlevel 1 (
    set DEV=%USB_DEV%
    echo   [USB] 连接成功  %USB_DEV%
    goto :launch
)

echo.
echo   [错误] 设备未连接!
echo   WiFi: 确保手机和电脑在同一局域网
echo   USB:  确保已连接数据线并授权ADB
echo.
pause
exit /b 1

:launch
echo.
echo [2/2] 启动 scrcpy 投屏...
echo   设备: !DEV!    分辨率: 1280    码率: 4M    帧率: 30
echo   (关闭窗口或 Ctrl+C 可断开投屏)
echo.
"%SCRCPY%" -s !DEV! --max-size 1280 --video-bit-rate 4M --max-fps 30 --stay-awake --turn-screen-off

pause

