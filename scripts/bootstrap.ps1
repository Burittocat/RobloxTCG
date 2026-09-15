# 아무것도 깔려 있지 않은 윈도우에서 이 저장소를 개발 가능한 상태로 만든다.
#
#   scripts\bootstrap.cmd              rojo · lune 을 .tools\ 에 받는다
#   scripts\bootstrap.cmd -Persist     PATH 에도 영구히 얹는다 (HKCU, 관리자 불필요)
#   scripts\bootstrap.cmd -Force       이미 받은 것도 다시 받는다
#
# 왜 aftman 을 안 쓰나:
# aftman 은 처음 도구를 부를 때 "이 도구를 믿습니까" 를 물어서, 스크립트가 대신
# 답해줄 수 없다. 필요한 건 실행 파일 두 개뿐이라 GitHub 릴리스에서 바로 받는다.
# 버전은 aftman.toml 을 읽어서 쓰므로 **CI 와 같은 버전**이 보장된다.
#
# 관리자 권한은 어디에도 필요 없다. 받은 것은 전부 저장소 안 .tools\ 에 들어가고,
# -Persist 도 HKCU(내 계정) 의 PATH 만 건드린다.
#
# 여기서 다루지 않는 것 — 설치 관리자가 필요한 것들이다:
#   Git          PortableGit (.7z.exe, 압축만 풀린다)
#   VS Code      User Installer (%LOCALAPPDATA% 로 들어간다)
#   Roblox Studio + Rojo 플러그인 (Rojo.rbxm → %LOCALAPPDATA%\Roblox\Plugins)
# 자세한 건 docs/getting-started.md 참조.

param(
    [switch]$Persist,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 은 기본 프로토콜에 TLS 1.2 가 없을 수 있다.
# 그러면 github.com 에서 "기본 연결이 닫혔습니다" 로 끝난다.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$toolsDir = Join-Path $repo '.tools'
$stamp = Join-Path $toolsDir '.versions'

function Write-Step($text) { Write-Host "> $text" -ForegroundColor DarkGray }
function Write-Ok($text) { Write-Host "  $text" -ForegroundColor Green }
function Write-Warn2($text) { Write-Host "  $text" -ForegroundColor Yellow }

# ── aftman.toml 이 유일한 버전 출처 ──────────────────────────────────────────
# rojo = "rojo-rbx/rojo@7.7.0"  →  이름 rojo · 소유자 rojo-rbx · 버전 7.7.0
$manifest = Join-Path $repo 'aftman.toml'
if (-not (Test-Path $manifest)) {
    Write-Host "aftman.toml 이 없습니다. 저장소 안에서 실행하세요." -ForegroundColor Red
    exit 1
}

$tools = @()
foreach ($line in Get-Content $manifest) {
    if ($line -match '^\s*([A-Za-z0-9_-]+)\s*=\s*"([^/]+)/([^@]+)@(.+)"\s*$') {
        $tools += [pscustomobject]@{
            Name    = $Matches[1]
            Owner   = $Matches[2]
            Repo    = $Matches[3]
            Version = $Matches[4]
        }
    }
}

if ($tools.Count -eq 0) {
    Write-Host "aftman.toml 에서 도구를 읽지 못했습니다." -ForegroundColor Red
    exit 1
}

# ── 아키텍처 ────────────────────────────────────────────────────────────────
# rojo·lune 둘 다 windows-x86_64 / windows-aarch64 로 올라온다.
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }

# ── 이미 받아둔 것 건너뛰기 ─────────────────────────────────────────────────
$want = ($tools | ForEach-Object { "$($_.Name)=$($_.Version)" }) -join ';'
$have = if (Test-Path $stamp) { (Get-Content $stamp -Raw).Trim() } else { '' }

if (-not $Force -and $have -eq $want -and (Test-Path $toolsDir)) {
    $allThere = $true
    foreach ($tool in $tools) {
        if (-not (Test-Path (Join-Path $toolsDir "$($tool.Name).exe"))) { $allThere = $false }
    }
    if ($allThere) {
        Write-Ok "이미 받아둔 것이 aftman.toml 과 같습니다 ($want). 다시 받으려면 -Force."
        $skipDownload = $true
    }
}

if (-not $skipDownload) {
    New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

    foreach ($tool in $tools) {
        $asset = "$($tool.Name)-$($tool.Version)-windows-$arch.zip"
        $url = "https://github.com/$($tool.Owner)/$($tool.Repo)/releases/download/v$($tool.Version)/$asset"
        $zip = Join-Path $env:TEMP $asset

        Write-Step "$($tool.Name) $($tool.Version) 받는 중"
        try {
            # 진행 표시줄을 끄면 Invoke-WebRequest 가 눈에 띄게 빨라진다.
            $prev = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            $ProgressPreference = $prev
        } catch {
            Write-Host "  받지 못했습니다: $url" -ForegroundColor Red
            Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }

        Expand-Archive -Path $zip -DestinationPath $toolsDir -Force
        Remove-Item $zip -Force

        $exe = Join-Path $toolsDir "$($tool.Name).exe"
        if (-not (Test-Path $exe)) {
            Write-Host "  압축 안에 $($tool.Name).exe 가 없습니다." -ForegroundColor Red
            exit 1
        }
        Write-Ok "$toolsDir\$($tool.Name).exe"
    }

    Set-Content -Path $stamp -Value $want -Encoding ascii
}

# ── 이 창의 PATH ────────────────────────────────────────────────────────────
$env:PATH = "$toolsDir;$env:PATH"

Write-Host ""
Write-Step "버전 확인"
foreach ($tool in $tools) {
    $out = & (Join-Path $toolsDir "$($tool.Name).exe") --version 2>&1
    Write-Ok "$out"
}

# ── PATH 에 영구히 얹기 (선택) ──────────────────────────────────────────────
# HKCU 의 사용자 PATH 만 건드린다. 관리자 권한이 필요 없고 다른 사용자에게
# 영향도 없다. 기계 전체(HKLM) PATH 는 절대 손대지 않는다.
if ($Persist) {
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -and ($userPath -split ';') -contains $toolsDir) {
        Write-Ok "PATH 에 이미 있습니다."
    } else {
        $newPath = if ([string]::IsNullOrEmpty($userPath)) { $toolsDir } else { "$toolsDir;$userPath" }
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        Write-Ok "사용자 PATH 에 추가했습니다 — 새로 여는 창부터 적용됩니다."
    }
}

# ── 나머지 한 번짜리 설정 ───────────────────────────────────────────────────
Write-Host ""
Write-Step "커밋 훅"
$hooksPath = (& git config core.hooksPath) 2>$null
if ($hooksPath -eq '.githooks') {
    Write-Ok "이미 켜져 있습니다."
} else {
    & git config core.hooksPath .githooks
    Write-Ok "켰습니다 — 커밋할 때마다 로컬 CI 와 문서 동기화 검사가 돕니다."
}

Write-Step "Lune 타입 정의 (에디터가 @lune/* 를 알아보게 한다)"
& (Join-Path $toolsDir 'lune.exe') setup | Out-Null
Write-Ok ".lune/ 생성"

Write-Host ""
Write-Host "준비 끝." -ForegroundColor Green
Write-Host ""
Write-Host "  scripts\ci.cmd        검사 전부 돌려보기" -ForegroundColor DarkGray
Write-Host "  lune run play         터미널에서 한 판" -ForegroundColor DarkGray
Write-Host "  scripts\studio.cmd    Studio 로 열기 (Studio 가 깔려 있을 때)" -ForegroundColor DarkGray

if (-not $Persist) {
    Write-Host ""
    Write-Warn2 "이 창에서만 PATH 가 잡혀 있습니다."
    Write-Warn2 "새 창에서도 쓰려면: scripts\bootstrap.cmd -Persist"
}
