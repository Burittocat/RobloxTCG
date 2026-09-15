# 실행하고 개발하기

Studio 에서 게임을 켜는 법, 터미널에서 한 판 돌리는 법, VS Code 개발 환경을 갖추는 법.
처음 클론했다면 여기부터 읽는다.

---

## 아무것도 깔려 있지 않은 컴퓨터에서 (학교 컴퓨터 등)

**관리자 권한은 필요 없다.** 아래 전부 내 계정 폴더 안에서 끝난다.

### 1. Git 과 VS Code

| | 받는 것 | 어디로 들어가나 |
|---|---|---|
| Git | **PortableGit** (`.7z.exe` — 설치가 아니라 압축 해제다) | 원하는 폴더 |
| VS Code | **User Installer** (System Installer 가 아니다) | `%LOCALAPPDATA%\Programs` |

둘 다 관리자 권한을 묻지 않는다. System Installer 를 고르면 그때부터 막힌다.

### 2. 저장소와 도구

```powershell
git clone https://github.com/Burittocat/RobloxTCG.git
cd RobloxTCG
scripts\bootstrap.cmd
```

`bootstrap.cmd` 가 하는 일:

- `aftman.toml` 을 읽어 **거기 적힌 버전 그대로** rojo·lune 을 받아 `.tools\` 에 넣는다
  (CI 와 같은 버전이 보장된다 — 버전이 갈리면 "내 컴에선 되는데" 가 생긴다)
- 커밋 훅을 켠다 (`git config core.hooksPath .githooks`)
- `lune setup` 으로 에디터용 타입 정의를 만든다

```powershell
scripts\bootstrap.cmd -Persist   # 새 창에서도 쓰도록 사용자 PATH 에 얹는다 (HKCU, 관리자 불필요)
scripts\bootstrap.cmd -Force     # 이미 받은 것도 다시 받는다
```

`-Persist` 를 안 쓰면 **그 창에서만** PATH 가 잡힌다. `scripts\ci.cmd` 나 VS Code 작업은
`.tools\` 를 직접 찾으므로 그대로 돌아간다.

**aftman 은 쓰지 않는다.** 처음 도구를 부를 때 "이 도구를 믿습니까" 를 물어서 스크립트가
대신 답할 수 없고, 어차피 필요한 건 실행 파일 두 개뿐이다. 집 컴퓨터처럼 이미 aftman 이
깔려 있다면 그쪽이 그대로 쓰인다 — `scripts/ci.sh` 가 두 곳을 다 본다.

### 3. Roblox Studio (화면을 봐야 할 때만)

Studio 는 `%LOCALAPPDATA%\Roblox` 로 들어가므로 보통 관리자 권한이 필요 없다.
다만 **학교 네트워크가 Roblox 를 막아둔 경우** 설치도 로그인도 안 된다.

Rojo 의 Studio 플러그인은 마켓플레이스를 거치지 않고도 넣을 수 있다 —
[Rojo 릴리스](https://github.com/rojo-rbx/rojo/releases)의 `Rojo.rbxm` 을 받아
`%LOCALAPPDATA%\Roblox\Plugins\` 에 복사하면 끝이다.

### Studio 없이 할 수 있는 것

| | 필요한 것 |
|---|---|
| 테스트 152개 (`scripts\ci.cmd`) | **lune 만** |
| 터미널에서 한 판 (`lune run play`) | **lune 만** |
| AI 자기대국 · 카드 표 확인 | **lune 만** |
| 플레이스 빌드 · 에디터 자동완성 | + rojo |
| **연출을 눈으로 확인** | **Studio 가 있어야 한다** |

룰·AI·네트워크는 전부 Studio 없이 검증된다. 반대로 **순수 연출은 테스트가 못 잡으므로**
(`Theme.motion` 의 숫자가 맞는지는 돌려봐야 안다) Studio 가 없는 환경에서는
연출 작업을 잡지 않는 편이 낫다.

---

## Studio 에서 바로 플레이하기

처음 한 번만 (`scripts\bootstrap.cmd` 를 돌렸다면 이미 끝나 있다):

```powershell
aftman install          # rojo 7.7.0 + lune 0.10.4 설치
lune setup              # 에디터용 Lune 타입 정의 (tests/ 의 @lune/* 를 알아보게 한다)
```

플레이스 파일을 만들어 여는 방법 (가장 빠름):

```powershell
scripts\studio.cmd      # 검사를 전부 돌린 뒤 Studio 로 연다
```

**확장자 `.cmd` 까지 붙여서** 부른다. 이유가 둘이다.

- 윈도우의 기본 실행 정책이 `Restricted` 라 `.\scripts\studio.ps1` 은
  "스크립트를 실행할 수 없으므로" 로 막힌다. `.cmd` 가 이번 실행에만 Bypass 를 주고
  `.ps1` 을 부르므로 컴퓨터 설정을 바꾸지 않아도 된다.
- 확장자를 빼고 `scripts\studio` 라고만 치면 **PowerShell 이 `.cmd` 가 아니라 `.ps1` 을
  먼저 고른다.** 그러면 위의 실행 정책에 그대로 막힌다.

`scripts/` 안의 윈도우 스크립트는 인코딩 규칙이 나머지와 다르다. `.gitattributes` 가
못 박아두고 있으니 새로 만들 때 맞춰야 한다.

| | 인코딩 | 줄바꿈 | 왜 |
|---|---|---|---|
| `*.cmd` | **ASCII 만** | CRLF | cmd.exe 는 OEM 코드페이지로 읽고 CRLF 를 요구한다. 한글 주석을 넣으면 깨지면서 그 줄을 명령으로 실행하려 든다 |
| `*.ps1` | **UTF-8 + BOM** | CRLF | Windows PowerShell 5.1 은 BOM 이 없으면 CP949 로 읽는다. 한글이 깨지며 따옴표가 어긋나 파일 전체가 파싱 실패한다 |
| `*.sh` · `*.luau` | UTF-8 (BOM 없이) | LF | sh 와 Lune 은 BOM 을 문법 오류로 본다 |

검사를 건너뛰고 바로 열려면:

```powershell
rojo build --output build.rbxlx
start build.rbxlx       # Studio 가 열린다 → F5(Play)
```

`start` 가 "이 파일을 어떻게 열까요" 를 물으면 `.rbxlx` 파일 연결이 없는 것이다.
`studio.ps1` 은 그 경우에도 되도록 Studio 실행 파일을 직접 찾아서 넘긴다.

검사를 먼저 돌리는 편이 결국 빠르다 — Studio 는 스크립트가 죽어도 게임을 계속 돌리므로,
출력창을 안 보고 있으면 "왜 버튼이 안 먹지" 를 화면만 보며 한참 헤매게 된다.

> **Studio 에서 저장하지 말 것.** `build.rbxlx` 는 `rojo build` 가 만드는 산출물이다.
> Studio 에서 `Ctrl+S` 를 누르면 그 파일을 Studio 가 저장한 버전으로 덮어쓰고, 그 창에서
> 그대로 게시하면 **그때 열려 있던 낡은 코드가 올라간다.** (Studio 가 저장한 파일은
> 지형·카메라 같은 걸 덧붙여서 rojo 산출물보다 눈에 띄게 커진다 — 구분하는 단서다)
> 고친 걸 반영하려면 창을 닫고 `scripts\studio.cmd` 를 다시 돌린다.

VS Code 에서 고치면서 Studio 에 실시간 반영하는 방법 (개발할 때 이쪽):

```powershell
rojo serve              # 터미널에 남겨둔다
```

그다음 Studio 에서 플러그인 툴바의 **Rojo → Connect**. 이후 파일을 저장할 때마다
Studio 트리가 갱신된다.

F5 를 누르면 **시작 화면**이 뜬다.

| 버튼 | 하는 일 |
|---|---|
| **빠른 대전** | 큐에 서서 사람을 찾는다. 찾으면 대전 서버로 옮겨져 한 판이 시작된다 |
| **AI 연습** | 큐를 타지 않고 이 서버에서 바로 AI 와 한 판 |

혼자 테스트할 때는 **AI 연습**이 빠르다. 매칭까지 확인하려면 Studio 의 테스트 탭에서
플레이어 수를 **2명**으로 놓고 시작한 뒤, 두 창에서 각각 빠른 대전을 누른다
(Studio 는 텔레포트가 안 되므로 같은 서버 안에서 붙는다 — 아래 '매칭' 참조).

전투 조작은 전부 마우스다.

| 상황 | 할 일 |
|---|---|
| 메인 페이즈 | 손패 카드를 클릭 → 코스트/생물/마법이 나간다 |
| 대상이 필요한 마법 | 초록 테두리가 켜진 생물·플레이어·스택 항목을 클릭 |
| 공격준비 | 내 생물 클릭 → 공격할 대상 클릭 |
| 수비준비 | 내 생물 클릭 → 막을 공격자 클릭 |
| 상대가 뭔가 시전 | `대응 패스` 또는 '즉시시전' 마법으로 응수 |

`E` 페이즈 종료 · `P` 대응 패스 · `Esc` 선택 취소 · `L` 로그 ·
`R` 새 판(AI 연습이 끝난 뒤에만. PvP 는 매칭을 다시 타야 한다).

판이 끝나면 결과 화면에 버튼 두 개가 뜬다 — PvP 면 **다시 매칭 / 나가기**,
AI 연습이면 **다시 하기 / 로비로**.

### Studio 에서 확인할 것

서버 출력창에 이 셋이 찍히면 정상이다.

```
[TCG] 카드 32 장 등록 완료
[TCG] 매칭 백엔드: 같은 서버 (Studio 테스트용)
[TCG] 로비 서버 준비 완료 — 빠른 대전 큐가 열렸습니다
```

| 확인 | 어떻게 |
|---|---|
| 시작 화면 | F5 → **빠른 대전 / AI 연습** 두 버튼 |
| AI 한 판 | **AI 연습** → 손패 클릭 · `E` 로 페이즈 진행 |
| 2인 매칭 | 테스트 탭에서 플레이어 **2명** → 두 창 모두 **빠른 대전** → 2초 안에 붙는다 |
| 좌석 | 두 창에서 각자의 이름이 **아래칸**에 있어야 한다 |
| 몰수 | 한 창을 닫으면 남은 창에 **승리** 가 뜬다 |

Studio 에서는 텔레포트가 안 되므로 매칭이 같은 서버 안에서 일어난다
(출력창의 "매칭 백엔드" 줄이 그 사실을 알려준다). 크로스서버 경로는 게시한 뒤에만 돈다 —
그 대신 `tests/smoke.luau` 가 흉내낸 환경에서 검증한다.

---

## 터미널에서 한 판 하기

```powershell
lune run play          # 사람(P1) vs AI(P2)
```

Studio 를 켜지 않고 룰만 빠르게 확인할 때 쓴다.
**게임 안에서 도는 것과 완전히 같은 룰 엔진 코드**를 호출하므로,
여기서 이상하면 게임 안에서도 이상하다.

```
숫자      문맥에 맞는 기본 행동 (패 내기 / 공격 선언 / 방어 배정)
h <번호>  손패에서 카드 내기 (어느 페이즈든)
e         페이즈 종료
p         스택 대응 패스
l         최근 로그      ?  도움말      q  종료
```

번호가 가리키는 대상은 페이즈에 따라 바뀐다 — 메인이면 손패, 공격준비면 내 생물,
수비준비면 방어할 생물. 화면 위에 항상 표시된다.

---

## VS Code 에서 개발하기

폴더를 열면 확장 3개를 권한다 (`.vscode/extensions.json`).

| 확장 | 역할 |
|---|---|
| **luau-lsp** | 자동완성 · 타입체크 · Roblox API 정의 |
| **Rojo** | 명령 팔레트에서 Serve/Build |
| **StyLua** | 코드 정렬 (`stylua.toml` 규칙). **저장할 때 자동 정렬은 꺼져 있다** — [테스트와 CI](testing.md) 의 "왜 자동 정렬을 껐나" 참조 |

`.vscode/settings.json` 이 luau-lsp 의 **sourcemap 자동 생성**을 켜둔다.
sourcemap 은 "이 `.luau` 파일이 Studio 트리의 어디인가" 를 담은 표이고,
이게 있어야 `require(script.Parent.UI.Battle)` 같은 경로를 에디터가 따라간다.
`rojo` 가 PATH 에 있으면(= `aftman install` 을 했으면) 알아서 만들어진다.

`tests/` 는 Roblox 가 아니라 Lune 위에서 돈다. `lune setup` 이 만든 타입 정의를
`.luaurc` 의 `aliases` 가 가리키고 있어서 `require("@lune/fs")` 같은 줄에 빨간 줄이
뜨지 않는다. **클론 직후 한 번은 `lune setup` 을 돌려야 한다** — 정의가 저장소가 아니라
홈 디렉터리(`~/.lune/.typedefs/`)에 깔리기 때문이다.

`.luaurc` 의 `lint` 이름은 **Luau 가 아는 것만** 써야 한다. 없는 이름을 하나라도 적으면
`.luaurc` 전체가 거부돼서 타입 검사와 린트가 통째로 꺼진다 (에디터는 조용히 아무것도
지적하지 않게 된다). 유효한 이름 목록은 luau-lsp 확장의 `schemas/luaurc.json` 에 있다.

명령줄에서 에디터와 같은 검사를 돌려볼 수도 있다. luau-lsp 확장이 들고 있는 실행
파일을 쓴다 — CI 에는 안 넣었다. 확장 경로가 사람마다 다르고 버전마다 바뀌기 때문이다.

```powershell
$srv = "$env:USERPROFILE\.vscode\extensions\johnnymorganz.luau-lsp-*\bin\server.exe"
& (Resolve-Path $srv)[0] analyze --sourcemap sourcemap.json --base-luaurc .luaurc (Get-ChildItem src -Recurse -Filter *.luau)
```

`Ctrl+Shift+B` / 작업 실행에 미리 넣어둔 것들 (`.vscode/tasks.json`):

```
로컬 CI (문법 · 테스트 · 빌드)  ← 기본 빌드 작업
커밋 훅 켜기                    이 저장소에서 한 번만
rojo: serve                     Studio 실시간 연결
rojo: build                     build.rbxlx 생성
문법 검사                       lune run tests/check.luau
테스트 (룰 엔진)                lune run tests/run.luau   ← 기본 테스트 작업
스모크 테스트                    lune run tests/smoke.luau
Studio 에서 열기 (검사 후)       scripts\studio.cmd
터미널 싱글플레이                lune run play
AI 자동 대전                    lune run play -- --auto
```

명령줄로도 같다:

```powershell
lune run tests/check.luau # 전체 .luau 문법 검사 (65개 파일)
lune run tests/run.luau   # 룰 · 네트워크 · 매칭 · 덱 · 클라이언트 판정 (161개)
lune run play -- --auto   # AI vs AI 자동 대전 (룰 구경용)
lune run play -- --seed 42
```
