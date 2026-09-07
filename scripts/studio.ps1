# 검사를 전부 돌린 뒤 플레이스를 만들어 Studio 로 연다. (PowerShell 용)
#
#   .\scripts\studio.ps1
#
# scripts/studio.sh 와 같은 일을 한다. 따로 있는 이유는 둘이다.
#
#   1. 윈도우 PowerShell 에는 `sh` 가 없다. Git 이 sh.exe 를 깔아두지만 PATH 에
#      올려주지 않아서, `sh scripts/studio.sh` 는 "명령을 찾을 수 없음" 으로 끝난다.
#   2. .rbxlx 파일 연결이 없으면 `start build.rbxlx` 도 실패한다. 그래서 여기서는
#      Studio 실행 파일을 직접 찾아 넘긴다.
#
# 검사 목록은 여기 없다 — scripts/ci.sh 하나가 사람·훅·GitHub 의 유일한 기준이고,
# 이 스크립트는 그걸 부르기만 한다.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# aftman 이 깐 도구는 ~/.aftman/bin 에 있다.
$env:PATH = "$env:USERPROFILE\.aftman\bin;$env:PATH"

#--------------------------------------------------------------------------
# sh.exe 찾기 (Git for Windows 가 깔아둔 것)
#--------------------------------------------------------------------------
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

#--------------------------------------------------------------------------
# 검사
#--------------------------------------------------------------------------
& $sh scripts/ci.sh --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "검사가 실패해서 Studio 를 열지 않습니다." -ForegroundColor Red
    exit 1
}

#--------------------------------------------------------------------------
# 지금 여는 것이 어느 코드인지
#
# Studio 에서 Ctrl+S 를 누르면 build.rbxlx 를 Studio 가 저장한 파일로 덮어쓴다.
# 그 창에서 그대로 게시하면 그때 열려 있던(= 낡았을 수 있는) 코드가 올라간다.
#--------------------------------------------------------------------------
$commit = git rev-parse --short HEAD 2>$null
if (-not $commit) { $commit = '커밋 없음' }

$dirty = ''
git diff --quiet 2>$null
if ($LASTEXITCODE -ne 0) { $dirty = ' + 커밋 안 된 변경' }

Write-Host ""
Write-Host "  게시할 코드 : $commit$dirty" -ForegroundColor Cyan
Write-Host "  Studio 에서 저장(Ctrl+S)하지 마세요 — build.rbxlx 는 rojo 가 만드는 산출물입니다." -ForegroundColor DarkGray
Write-Host ""

#--------------------------------------------------------------------------
# Studio 로 열기
#
# 버전 폴더 이름(version-<해시>)은 Studio 가 갱신될 때마다 바뀌므로 박아둘 수 없다.
# 가장 최근 것을 찾아 쓴다.
#--------------------------------------------------------------------------
$studio = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Filter 'RobloxStudioBeta.exe' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName

if ($studio) {
    & $studio (Join-Path $repo 'build.rbxlx')
} else {
    # Studio 를 못 찾으면 파일 연결에 맡긴다. 연결도 없으면 윈도우가 물어본다.
    Write-Host "Studio 실행 파일을 못 찾아 파일 연결로 엽니다." -ForegroundColor Yellow
    Invoke-Item (Join-Path $repo 'build.rbxlx')
}
