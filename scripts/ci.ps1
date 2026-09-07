# 로컬 CI. (PowerShell 용)
#
#   .\scripts\ci.ps1
#   .\scripts\ci.ps1 -Quiet
#
# 윈도우 PowerShell 에는 `sh` 가 없어서 `sh scripts/ci.sh` 가 그냥 안 돈다.
# Git 이 sh.exe 를 깔아두지만 PATH 에 올려주지 않기 때문이다.
#
# 검사 목록은 여기 없다. scripts/ci.sh 하나가 사람·커밋 훅·GitHub 의 유일한 기준이고
# 이 스크립트는 그걸 부르기만 한다 — 목록이 두 곳에 있으면 반드시 어긋난다.

param([switch]$Quiet)

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$env:PATH = "$env:USERPROFILE\.aftman\bin;$env:PATH"

$sh = (Get-Command sh -ErrorAction SilentlyContinue).Source
if (-not $sh) {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\sh.exe",
        "${env:ProgramFiles(x86)}\Git\bin\sh.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\sh.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $sh = $c; break }
    }
}
if (-not $sh) {
    Write-Host "sh.exe 를 찾지 못했습니다. Git for Windows 가 설치돼 있어야 합니다." -ForegroundColor Red
    exit 1
}

if ($Quiet) { & $sh scripts/ci.sh --quiet } else { & $sh scripts/ci.sh }
exit $LASTEXITCODE
