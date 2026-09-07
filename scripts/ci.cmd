@echo off
rem Run the local CI checks.
rem
rem   scripts\ci.cmd
rem
rem ASCII + CRLF on purpose, and -ExecutionPolicy Bypass so the default
rem Restricted policy does not block the .ps1 it calls. See scripts\studio.cmd.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ci.ps1" %*
