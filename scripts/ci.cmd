@echo off
rem 로컬 CI 를 돌린다.
rem
rem   scripts\ci
rem
rem 윈도우 기본 실행 정책(Restricted)에 막히지 않도록 이번 실행에만 Bypass 를 준다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ci.ps1" %*
