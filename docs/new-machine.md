# 새 컴퓨터에서 처음부터

학교 컴퓨터처럼 **아무것도 깔려 있지 않고 관리자 권한도 없는** 윈도우에서,
코드를 받아 고치고 **그날 작업을 집으로 가져가기까지**. 위에서부터 그대로 따라가면 된다.

**관리자 권한은 어디에도 필요 없다.** 전부 내 계정 폴더 안에서 끝난다.

## 한눈에

| | 하는 일 | 빠뜨리면 |
|---|---|---|
| [1](#1-손으로-깔-것--셋뿐이다) | Git · VS Code 설치 (Studio 는 화면을 볼 때만) | 아무것도 시작이 안 된다 |
| [2](#2-클론) | `git clone` | |
| [3](#3-내가-누구인지-알려준다) | `git config user.name` / `user.email` | **커밋이 거부된다** |
| [4](#4-도구-받기) | `scripts\bootstrap.cmd -Persist` | `lune` · `rojo` 가 없다 |
| [5](#5-vs-code-확장) | 확장 셋 설치 | 자동완성과 Studio 연결이 없다 |
| [6](#6-studio-쪽-화면을-볼-때만) | Studio + API 접근 허용 | 덱 저장이 **조용히** 실패한다 |
| [7](#7-다-됐는지-확인) | `scripts\ci.cmd` | |
| [8](#8-오늘-작업을-집으로-가져가기) | 커밋 · 푸시 (GitHub 인증) | **오늘 한 일이 그 컴퓨터에 갇힌다** |

3번과 8번이 이 문서에서 제일 자주 막히는 곳이다. 나머지는 대체로 그냥 된다.

---

## 0. 지금 뭐가 있는지

```powershell
git --version       # 없으면 1번
code --version      # 없으면 1번
```

## 1. 손으로 깔 것 — 셋뿐이다

rojo·lune 은 깔지 않는다. 4번의 `bootstrap.cmd` 가 받아온다.

| | 어디서 | 무엇을 고르나 | 어디로 들어가나 |
|---|---|---|---|
| **Git** | [git-scm.com/download/win](https://git-scm.com/download/win) | **Portable ("thumbdrive edition")** — 설치가 아니라 압축 해제다 | 원하는 폴더 |
| **VS Code** | [code.visualstudio.com/Download](https://code.visualstudio.com/Download) | **User Installer** (System Installer 가 아니다) | `%LOCALAPPDATA%\Programs` |
| **Roblox Studio** | [roblox.com/create](https://www.roblox.com/create) | Studio 시작 → 설치 | `%LOCALAPPDATA%\Roblox` |

- **System Installer 를 고르면 그때부터 막힌다.** VS Code 는 반드시 User Installer.
  일반 Git 설치 관리자를 쓸 거면 설치 위치를 `%LOCALAPPDATA%` 아래로 바꾼다.
- **Git 은 뺄 수 없다.** VS Code 는 git 을 들고 오지 않는다(설치 폴더에 `git.exe` 가 없다).
  그리고 GitHub 의 **"Download ZIP" 으로 받으면 안 된다** — `.git` 이 없으면 커밋도 푸시도
  훅도 안 되고, 작업을 이어서 하려면 결국 푸시를 해야 한다.
- Studio 는 **화면을 볼 때만** 필요하다. 없어도 룰·AI 작업은 그대로 된다
  ([아래 표](#studio-없이-되는-것--안-되는-것)).

Portable Git 을 썼다면 그 폴더의 `cmd\` 를 PATH 에 넣거나, 딸려 오는
**Git Bash** 를 열어서 아래를 진행한다.

## 2. 클론

```powershell
git clone https://github.com/Burittocat/RobloxTCG.git
cd RobloxTCG
```

**이 저장소는 공개라 받는 데는 로그인이 필요 없다.** 로그인은 8번(푸시)에서 처음 필요하다 —
그러니 인증에서 막히더라도 개발은 먼저 시작할 수 있다.

## 3. 내가 누구인지 알려준다

```powershell
git config --global user.name  "내이름"
git config --global user.email "내메일@example.com"
```

**이게 가장 자주 막히는 곳이다.** 새 컴퓨터의 git 은 커밋한 사람이 누구인지 모르고,
모르는 채로는 커밋을 **거부한다**. 그런데 그 사실은 몇 시간 작업한 뒤 처음 커밋할 때에야
드러난다 — *Please tell me who you are*.

이 저장소에 이미 올라간 커밋과 같은 사람으로 잡히게 하려면 **GitHub 계정에 등록된 메일**을
쓴다. 다른 메일로 커밋하면 커밋은 되지만 GitHub 에서 내 것으로 안 보인다.

> 공용 컴퓨터라 전역 설정을 남기기 싫으면 `--global` 을 빼고 저장소 안에서 돌린다.
> 그 폴더에만 적용되고, 폴더를 지우면 같이 사라진다.

## 4. 도구 받기

```powershell
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

`-Persist` 를 안 쓰면 그 창에서만 PATH 가 잡힌다. 그래도 `scripts\ci.cmd` 와
VS Code 작업은 `.tools\` 를 직접 얹으므로 어느 쪽이든 돌아간다 — 터미널에서 `lune` 을
직접 치고 싶을 때만 `-Persist` 가 필요하다.

> **aftman 은 쓰지 않는다.** 처음 도구를 부를 때 "이 도구를 믿습니까" 를 물어서
> 스크립트가 대신 답할 수 없고, 어차피 필요한 건 실행 파일 두 개뿐이다.
> 집 컴퓨터처럼 이미 aftman 이 깔려 있으면 그쪽이 그대로 쓰인다 —
> `scripts/ci.sh` 가 두 곳을 다 본다.

## 5. VS Code 확장

VS Code 로 이 폴더를 열면 `.vscode/extensions.json` 이 셋을 권한다.

| 확장 | 하는 일 |
|---|---|
| `JohnnyMorganz.luau-lsp` | 자동완성 · 타입체크 · Roblox API 정의 |
| `evaera.vscode-rojo` | Studio 연결. **Rojo 의 Studio 플러그인도 이 확장이 넣어준다** |
| `JohnnyMorganz.stylua` | 코드 정렬 (저장할 때 자동 정렬은 꺼져 있다 — 이유는 아래) |

같은 파일이 **끄라고 표시해둔 둘**도 있다 — `undermywheel.roblox-lua` 와 `sumneko.lua` 는
`.luau` 를 두고 luau-lsp 와 다툰다. 깔려 있으면 확장 탭 → 톱니 → "사용 안 함(작업 영역)".

> **저장할 때 자동 정렬은 꺼 뒀다.** stylua 가 줄 길이를 **바이트로** 세는데 한글은
> 글자당 3바이트다. 화면에서 짧은 줄도 길다고 보고 한글 문자열을 쪼갠다.
> 필요하면 그 파일만 `Shift+Alt+F`.

`bootstrap.cmd -Persist` 로 PATH 를 얹었다면 **VS Code 를 껐다 켜야** 새 PATH 를 본다.
다만 VS Code 작업(`Ctrl+Shift+B` 등)은 PATH 와 무관하게 `.tools\` 를 먼저 보게 해 뒀다.

## 6. Studio 쪽 (화면을 볼 때만)

- **Rojo 플러그인은 따로 넣지 않아도 된다.** 5번의 `evaera.vscode-rojo` 가
  `%LOCALAPPDATA%\Roblox\Plugins\RojoManagedPlugin.rbxm` 으로 알아서 넣고 버전도 맞춘다.
  확장을 안 쓸 거면 [Rojo 릴리스](https://github.com/rojo-rbx/rojo/releases)의
  `Rojo.rbxm` 을 같은 폴더에 복사한다. 어느 쪽이든 마켓플레이스를 거치지 않는다.
- **게임 설정 → 보안 → "Studio 의 API 서비스 접근 허용"** 을 켠다. 꺼져 있으면
  덱 편집은 되는데 **저장만 조용히 실패한다.**

## 7. 다 됐는지 확인

```powershell
scripts\ci.cmd          # 문법 · 룰 엔진 · 스모크 · 문서 · 빌드
lune run play           # 터미널에서 AI 와 한 판
scripts\studio.cmd      # 검사 후 Studio 로 열기
```

`scripts\ci.cmd` 가 **로컬 CI 통과** 로 끝나면 준비가 끝난 것이다.
여기서 통과하면 GitHub 에 올려도 통과한다 (툴 버전이 같다).

> GitHub 의 **"코드 서식 (권고)" 잡은 원래 빨간불이다.** stylua 가 한글 줄 길이를
> 바이트로 세는 탓이고, `continue-on-error` 라 전체 결론은 성공이다.
> **빨간 표시를 보고 "내가 깼나" 하지 않는다.**

## 8. 오늘 작업을 집으로 가져가기

여기까지가 이 문서의 진짜 목적이다. **푸시하지 않으면 오늘 한 일은 그 컴퓨터에 갇힌다.**

### 커밋

```powershell
git add -A
git commit -m "무엇을 왜 바꿨는지"
```

커밋할 때 **훅이 로컬 CI 를 통째로 돌린다.** 30초쯤 걸리고, 실패하면 커밋이 안 된다 —
깨진 코드가 올라가지 않는다는 뜻이다. `--no-verify` 로 건너뛰지 않는다.

### 푸시 — 여기서 처음 로그인이 필요하다

```powershell
git push
```

받을 때와 달리 **올릴 때는 GitHub 이 내가 누구인지 확인한다.** 설치 관리자로 깐 Git 은
자격 증명 관리자를 같이 넣어두므로(`credential.helper=manager`), 처음 푸시할 때
**브라우저 창이 떠서 GitHub 로그인을 묻고** 그 뒤로는 안 묻는다.

브라우저가 안 뜨거나 학교에서 막혔다면 **토큰(PAT)** 으로 한다.

1. GitHub → Settings → Developer settings → **Personal access tokens (fine-grained)**
2. 이 저장소 하나만 고르고, 권한은 **Contents: Read and write**, 만료일은 짧게
3. `git push` 가 물으면 — 사용자 이름은 GitHub 아이디, **비밀번호 자리에 토큰**을 붙여넣는다

> **공용 컴퓨터라면 나올 때 지운다.** 토큰은 그 컴퓨터의 자격 증명 저장소에 남는다.
> `git credential-manager erase` 또는 윈도우 **자격 증명 관리자**에서
> `git:https://github.com` 항목을 지운다. 저장소 하나로 범위를 좁히고 만료일을 짧게
> 잡으라는 것도 같은 이유다 — 지우는 걸 잊어도 피해가 그 저장소·그 기간으로 끝난다.

### 집에 돌아와서

```powershell
git pull
```

**한쪽에서만 커밋하고 다른 쪽에서는 받기만 하는 편이 낫다.** 양쪽에서 커밋하면
합치는 일이 생기고, 이 저장소는 브랜치 없이 `main` 한 줄로만 간다.
작업 폴더가 둘 이상이면 시작할 때 **어느 쪽이 앞선지** 먼저 본다:

```powershell
git log --oneline -3
git status -sb
```

## Studio 없이 되는 것 / 안 되는 것

| | 필요한 것 |
|---|---|
| 테스트 전부 (`scripts\ci.cmd`) | **lune 만** |
| 터미널에서 한 판 (`lune run play`) | **lune 만** |
| AI 자기대국 · 카드 표 확인 | **lune 만** |
| 플레이스 빌드 · 에디터 자동완성 | + rojo |
| **연출을 눈으로 확인** | **Studio 가 있어야 한다** |

룰·AI·네트워크는 전부 Studio 없이 검증된다. 반대로 **순수 연출은 테스트가 못 잡으므로**
(`Theme.motion` 의 숫자가 맞는지는 돌려봐야 안다) Studio 가 없는 환경에서는
연출 작업을 잡지 않는 편이 낫다 — 캠페인 · BM 쪽이 낫다.

## 학교 네트워크가 막혀 있다면 — 집에서 USB 에 담아 가기

막히는 정도가 두 가지라 대처가 다르다. 먼저 학교에서 이걸 쳐 본다.

```powershell
git clone https://github.com/Burittocat/RobloxTCG.git
```

### 가) 클론은 되는데 bootstrap 만 실패한다

릴리스 파일을 받는 `objects.githubusercontent.com` 만 막힌 경우다. **`.tools\` 만 옮기면 된다.**

집에서:

```powershell
cd RobloxTCG
scripts\bootstrap.cmd          # .tools\ 가 만들어진다 (rojo.exe · lune.exe, 28MB)
```

`.tools\` 폴더를 통째로 USB 에 복사한다. **안에 있는 `.versions` 파일도 같이 가야 한다** —
숨김 파일이라 눈에 안 보이지만, 이게 있어야 학교에서 "이미 받아둔 것" 으로 알아보고
다시 받으려 들지 않는다. 폴더째 복사하면 따라간다.

학교에서 클론한 폴더 안에 `.tools\` 를 붙여넣고:

```powershell
scripts\bootstrap.cmd -Persist   # 받는 건 건너뛰고 훅과 타입 정의만 한다
```

### 나) 클론 자체가 안 된다

GitHub 이 통째로 막힌 경우다. **저장소 폴더를 통째로 USB 에 복사한다** —
`.git` 과 `.tools` 를 포함해서. 다 합쳐 30MB 쯤이다.

| 같이 가는 것 | 왜 |
|---|---|
| `.git\` | 이게 있어야 커밋이 되고, 원격 주소도 들어 있어 나중에 그대로 푸시된다 |
| `.tools\` | 받을 수가 없으니 |
| `.git\config` 안의 훅 설정과 이름·메일 | 집에서 잡아 뒀으면 따라간다 (3번을 다시 할 필요가 없다) |

학교에서 USB 폴더를 로컬 디스크로 옮긴 뒤 `scripts\bootstrap.cmd -Persist` 를 한 번 돌린다.
(USB 에서 바로 작업해도 되지만 느리고, 뽑을 때 사고가 난다)

**오프라인에서도 되는 것** — 실제로 네트워크 없이 돌려 확인했다:

- `scripts\ci.cmd` 전부 통과 (`lune setup` 은 바이너리에서 타입 정의를 만들어 낸다.
  0.05초에 끝나고 네트워크를 쓰지 않는다)
- `lune run play` 로 AI 와 한 판
- **커밋도 된다.** 훅까지 정상으로 돈다

푸시만 안 된다. 집에 돌아와서 `git push` 하면 그날 작업이 한꺼번에 올라간다.

### VS Code 확장 마켓플레이스도 막혔다면

확장 페이지의 **Download Extension** 으로 `.vsix` 를 받아 USB 에 담고, 학교에서:

```powershell
code --install-extension <파일>.vsix
```

셋 다 이렇게 넣을 수 있다. **`luau-lsp` 는 플랫폼별로 파일이 갈리므로 `win32-x64` 판을
받아야 한다.** 확장이 없어도 개발은 되지만 자동완성과 Studio 연결(Rojo)이 빠진다.

---

## 막혔을 때

| 증상 | 원인과 처방 |
|---|---|
| `git` 을 찾을 수 없습니다 | Portable Git 의 `cmd\` 가 PATH 에 없다. Git Bash 를 열어서 하거나 PATH 에 넣는다 |
| **Please tell me who you are** | 3번을 안 했다. 이름·메일을 잡고 다시 커밋한다 |
| bootstrap 이 "받지 못했습니다" | 학교 방화벽이 `objects.githubusercontent.com` 을 막는다 → 위 "집에서 USB 에 담아 가기" |
| "이 폴더는 git 저장소가 아닙니다" | ZIP 으로 받았다. 지우고 클론한다 |
| `sh.exe` 를 찾지 못했습니다 | Git 이 아예 없거나, Portable Git 이 PATH 에 없다. `ci.ps1` 은 PATH 의 `git.exe` 옆도 본다 |
| `lune` 를 찾을 수 없습니다 | `scripts\bootstrap.cmd` 를 안 돌렸다. 돌렸다면 `-Persist` 없이 연 새 창이다 |
| 푸시가 **403** 또는 인증 실패 | 토큰 권한이 모자라다 (Contents: Read and write) 또는 만료됐다. 자격 증명을 지우고 다시 |
| 커밋이 오래 걸린다 | 정상이다. 훅이 로컬 CI 를 통째로 돌린다 (30초쯤) |
| GitHub 의 "코드 서식" 이 빨갛다 | **원래 그렇다.** 7번의 주석 참조 — 전체 결론은 성공이다 |
| Studio 로그인이 안 된다 | 학교 네트워크가 Roblox 를 막는 경우다. 이땐 Studio 없이 되는 것만 한다 |
| 덱 저장만 실패한다 | 6번의 "API 서비스 접근 허용" 이 꺼져 있다 |
| 고쳤는데 Studio 에 반영이 안 된다 | `rojo serve` 를 띄우고 Studio 에서 Rojo → **Connect** 를 눌러야 한다 |

> **Studio 에서 `Ctrl+S` 를 누르지 않는다.** 스크립트가 아니라 플레이스를
> `build.rbxlx` 로 저장하는데, rojo 는 소스→Studio 단방향이라 되돌아오지 않는다.
> Studio 에서 고친 것은 창을 닫기 전에 VS Code 소스에 붙여넣어야 산다.

---

다음: [실행하고 개발하기](getting-started.md) — 개발 루프와 Studio 조작.
