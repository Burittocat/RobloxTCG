@echo off
rem Run all checks, then open the place in Roblox Studio.
rem
rem   scripts\studio.cmd
rem
rem Why this wrapper exists (see README, section 1):
rem   - Windows PowerShell blocks .ps1 by default (Restricted execution policy).
rem     Passing -ExecutionPolicy Bypass here avoids changing any machine setting.
rem   - This file is ASCII + CRLF on purpose. cmd.exe reads it with the OEM
rem     codepage and needs CRLF, so Korean comments here would break parsing.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0studio.ps1" %*
