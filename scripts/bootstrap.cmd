@echo off
rem Set up this repository on a machine with nothing installed.
rem
rem   scripts\bootstrap.cmd              download rojo + lune into .tools\
rem   scripts\bootstrap.cmd -Persist     also add .tools\ to the user PATH
rem   scripts\bootstrap.cmd -Force       re-download even if already present
rem
rem No administrator rights are needed. See scripts\studio.cmd for why this
rem ASCII + CRLF wrapper exists and why -ExecutionPolicy Bypass is passed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
