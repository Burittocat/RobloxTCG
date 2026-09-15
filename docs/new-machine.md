# 새 컴퓨터에서 처음부터

학교 컴퓨터처럼 **아무것도 깔려 있지 않고 관리자 권한도 없는** 환경에서
개발을 이어서 하기까지. 위에서부터 그대로 따라가면 된다.

**관리자 권한은 어디에도 필요 없다.** 전부 내 계정 폴더 안에서 끝난다.

---

## 0. 지금 뭐가 있는지

```powershell
git --version       # 없으면 1번
code --version      # 없으면 1번
```

## 1. 손으로 깔 것 — 셋뿐이다

rojo·lune 은 깔지 않는다. 2번의 `bootstrap.cmd` 가 받아온다.

| | 어디서 | 무엇을 고르나 | 어디로 들어가나 |
|---|---|---|---|
| **Git** | [git-scm.com/download/win](https://git-scm.com/download/win) | **Portable ("thumbdrive edition")** — 설치가 아니라 압축 해제다 | 원하는 폴더 |
| **VS Code** | [code.visualstudio.com/Download](https://code.visualstudio.com/Download) | **User Installer** (System Installer 가 아니다) | `%LOCALAPPDATA%\Programs` |
| **Roblox Studio** | [roblox.com/create](https://www.roblox.com/create) | Studio 시작 → 설치 | `%LOCALAPPDATA%\Roblox` |

- **System Installer 를 고르면 그때부터 막힌다.** VS Code 는 반드시 User Installer.
  일반 Git 설치 관리자를 쓸 거면 설치 위치를 `%LOCALAPPDATA%` 아래로 바꾼다.
- **Git 은 뺄 수 없다.** VS Code 는 git 을 들고 오지 않는다. 그리고 GitHub 의
  **"Download ZIP" 으로 받으면 안 된다** — `.git` 이 없으면 커밋도 푸시도 훅도 안 되고,
  작업을 이어서 하려면 결국 푸시를 해야 한다.
- Studio 는 **화면을 볼 때만** 필요하다. 없어도 룰·AI 작업은 그대로 된다 (아래 표).

Portable Git 을 썼다면 그 폴더의 `cmd\` 를 PATH 에 넣거나, 딸려 오는
**Git Bash** 를 열어서 아래를 진행한다.

## 2. 클론하고 도구 받기

```powershell
git clone https://github.com/Burittocat/RobloxTCG.git
cd RobloxTCG
scripts\bootstrap.cmd -Persist
```

`bootstrap.cmd` 가 하는 일 셋:

- `aftman.toml` 을 읽어 **거기 적힌 버전 그대로** rojo·lune 을 받아 `.tools\` 에 넣는다
  (CI 와 같은 버전이 보장된다 — 버전이 갈리면 "내 컴에선 되는데" 가 생긴다)
- 커밋 훅을 켠다 (`git config core.hooksPath .githooks`). **켰다고 말하기 전에 다시 읽어
  확인한다** — 못 켰으면 못 켰다고 말한다
- `lune setup` 으로 에디터용 타입 정의를 만든다

| 옵션 | |
|---|---|
| `-Persist` | 사용자 PATH(HKCU)에 `.tools\` 를 얹는다. **새로 여는 창부터** 적용된다 |
| `-Force` | 이미 받은 것도 다시 받는다 |

`-Persist` 를 안 쓰면 그 창에서만 PATH 가 잡힌다. `scripts\ci.cmd` 와 VS Code 작업은
`.tools\` 를 직접 찾으므로 어느 쪽이든 돌아간다.

> **aftman 은 쓰지 않는다.** 처음 도구를 부를 때 "이 도구를 믿습니까" 를 물어서
> 스크립트가 대신 답할 수 없고, 어차피 필요한 건 실행 파일 두 개뿐이다.
> 집 컴퓨터처럼 이미 aftman 이 깔려 있으면 그쪽이 그대로 쓰인다 —
> `scripts/ci.sh` 가 두 곳을 다 본다.

## 3. VS Code 확장

VS Code 로 이 폴더를 열면 `.vscode/extensions.json` 이 셋을 권한다.

| 확장 | 하는 일 |
|---|---|
| `JohnnyMorganz.luau-lsp` | 자동완성 · 타입체크 · Roblox API 정의 |
| `evaera.vscode-rojo` | Studio 연결. **Rojo 의 Studio 플러그인도 이 확장이 넣어준다** |
| `JohnnyMorganz.stylua` | 코드 정렬 (저장할 때 자동 정렬은 꺼져 있다) |

같은 파일이 **끄라고 표시해둔 둘**도 있다 — `undermywheel.roblox-lua` 와 `sumneko.lua` 는
`.luau` 를 두고 luau-lsp 와 다툰다. 깔려 있으면 확장 탭 → 톱니 → "사용 안 함(작업 영역)".

`bootstrap.cmd -Persist` 로 PATH 를 얹었다면 **VS Code 를 껐다 켜야** 새 PATH 를 본다.

## 4. Studio 쪽 (화면을 볼 때만)

- **Rojo 플러그인은 따로 넣지 않아도 된다.** 3번의 `evaera.vscode-rojo` 가
  `%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm` 으로 알아서 넣고 버전도 맞춘다.
  확장을 안 쓸 거면 [Rojo 릴리스](https://github.com/rojo-rbx/rojo/releases)의
  `Rojo.rbxm` 을 같은 폴더에 복사한다. 어느 쪽이든 마켓플레이스를 거치지 않는다.
- **게임 설정 → 보안 → "Studio 의 API 서비스 접근 허용"** 을 켠다. 꺼져 있으면
  덱 편집은 되는데 **저장만 조용히 실패한다.**

## 5. 다 됐는지 확인

```powershell
scripts\ci.cmd          # 문법 · 룰 152개 · 스모크 · 문서 · 빌드
lune run play           # 터미널에서 AI 와 한 판
scripts\studio.cmd      # 검사 후 Studio 로 열기
```

`scripts\ci.cmd` 가 **로컬 CI 통과** 로 끝나면 준비가 끝난 것이다.
여기서 통과하면 GitHub 에 올려도 통과한다 (툴 버전이 같다).

## Studio 없이 되는 것 / 안 되는 것

| | 필요한 것 |
|---|---|
| 테스트 152개 (`scripts\ci.cmd`) | **lune 만** |
| 터미널에서 한 판 (`lune run play`) | **lune 만** |
| AI 자기대국 · 카드 표 확인 | **lune 만** |
| 플레이스 빌드 · 에디터 자동완성 | + rojo |
| **연출을 눈으로 확인** | **Studio 가 있어야 한다** |

룰·AI·네트워크는 전부 Studio 없이 검증된다. 반대로 **순수 연출은 테스트가 못 잡으므로**
(`Theme.motion` 의 숫자가 맞는지는 돌려봐야 안다) Studio 가 없는 환경에서는
연출 작업을 잡지 않는 편이 낫다 — 겹쳐 막기 · 캠페인 · BM 쪽이 낫다.

## 막혔을 때

| 증상 | 원인과 처방 |
|---|---|
| `git` 을 찾을 수 없습니다 | Portable Git 의 `cmd\` 가 PATH 에 없다. Git Bash 를 열어서 하거나 PATH 에 넣는다 |
| bootstrap 이 "받지 못했습니다" | 학교 방화벽이 `github.com` / `objects.githubusercontent.com` 을 막는다. 집에서 `.tools\` 를 만들어 USB 로 옮겨도 된다 (exe 두 개뿐이다) |
| "이 폴더는 git 저장소가 아닙니다" | ZIP 으로 받았다. 지우고 클론한다 |
| `sh.exe` 를 찾지 못했습니다 | Git 이 아예 없거나, Portable Git 이 PATH 에 없다. `ci.ps1` 은 PATH 의 `git.exe` 옆도 본다 |
| `lune` 를 찾을 수 없습니다 | `scripts\bootstrap.cmd` 를 안 돌렸다 |
| Studio 로그인이 안 된다 | 학교 네트워크가 Roblox 를 막는 경우다. 이땐 Studio 없이 되는 것만 한다 |
| 덱 저장만 실패한다 | 4번의 "API 서비스 접근 허용" 이 꺼져 있다 |
| 고쳤는데 Studio 에 반영이 안 된다 | `rojo serve` 를 띄우고 Studio 에서 Rojo → **Connect** 를 눌러야 한다 |

> **Studio 에서 `Ctrl+S` 를 누르지 않는다.** 스크립트가 아니라 플레이스를
> `build.rbxlx` 로 저장하는데, rojo 는 소스→Studio 단방향이라 되돌아오지 않는다.
> Studio 에서 고친 것은 창을 닫기 전에 VS Code 소스에 붙여넣어야 산다.

---

다음: [실행하고 개발하기](getting-started.md) — 개발 루프와 Studio 조작.
