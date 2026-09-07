@echo off
rem 검사를 돌리고 Studio 로 연다.
rem
rem   scripts\studio
rem
rem .ps1 을 직접 부르지 않고 이 파일을 두는 이유: 윈도우의 기본 실행 정책이
rem Restricted 라서 `.\scripts\studio.ps1` 은 "스크립트를 실행할 수 없으므로" 로 막힌다.
rem 여기서 이번 실행에만 Bypass 를 주면, 컴퓨터 설정을 바꾸지 않고도 돌아간다.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0studio.ps1" %*
