@echo off
chcp 65001 >nul
title Мой дневник
cd /d "%~dp0"
python diary_desktop.py
if errorlevel 1 (
    echo.
    echo Не удалось запустить приложение.
    echo Убедитесь, что установлен Python 3 ^(python.org^).
    pause
)
