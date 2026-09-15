# 테스트와 CI

Studio 를 켜지 않고 게임을 검증하는 방법. 로컬 CI · GitHub Actions · 가짜 Roblox 위에서 도는 스모크 테스트.

---

## CI

검사 내용은 하나다 — `scripts/ci.sh`. 로컬 훅과 GitHub Actions 가 **같은 것**을 돌린다.

| 단계 | 하는 일 |
|---|---|
| 문법 검사 | `tests/check.luau` — 전체 `.luau` 컴파일 |
| 룰 테스트 | `tests/run.luau` — 룰 · AI 자기대국 · 네트워크 계약 · 매칭 · 덱 · 클라이언트 판정 (161개) |
| 스모크 테스트 | `tests/smoke.luau` — 서버와 클라이언트를 **실제로 실행** (50개) |
| 플레이스 빌드 | `rojo build` 가 실제로 성공하는지 |

넷 다 합쳐 2초쯤이다.

### 카드 수치 바꾸기

**`src/shared/Cards/Sheet.luau` 한 파일에서 바꾼다.** 한 줄이 카드 한 장이고,
이름·코스트·공격력·생명력·태그·설명이 그 줄에 다 있다.

```luau
--   id             이름          코스트 공격력 생명력  태그       설명
{ "CRE_GUARD",   "성문 경비병",   2,     2,     3,   "",        "" },
{ "CRE_HAWK",    "창공의 매",     2,     2,     1,   "비행",     "" },
{ "CRE_SCRIBE",  "종군 서기",     2,     1,     2,   "",        "소환하면 카드 1 장을 뽑는다." },
```

태그는 한글로 쓴다(`신속`·`비행`·`도발`·`원거리`·`즉시시전`, 쉼표로 여러 개).

**설명 칸에 태그 설명을 다시 쓰지 않는다.** "비행 — 지상 생물은…" 은 태그 자체의 규칙이라
`Enums.KeywordText` 한 곳에 있고, 카드를 오른쪽 클릭하면 거기서 읽어온다. 여기 또 쓰면
상세 화면에 같은 문장이 두 번 뜬다 — 실제로 그랬고, `lune run tests/run.luau` 가
이제 태그 이름으로 시작하는 설명을 걸러낸다. 이 칸에는 그 카드만의 이야기를 쓰고,
태그밖에 없는 카드는 비워둔다.
마법은 효과 칸에 `damage(3, "생물또는플레이어")`, `draw(2)`, `destroy("적생물")` 처럼 적는다 —
쓸 수 있는 것 전부가 그 파일 맨 위 주석에 있다.

바꾼 뒤:

```powershell
lune run tests/cards.luau           # 지금 값이 표로 나온다. 잘못된 값도 여기서 잡힌다
lune run tests/cards.luau -- GUARD  # 일부만 보기 (id 조각으로 거른다)
lune run tests/balance.luau         # 판이 어떻게 달라졌는지 AI 자기대국으로 잰다
```

오타를 내면 게임이 뜬 뒤가 아니라 도구에서 한 줄로 잡힌다:

```
카드 표(src/shared/Cards/Sheet.luau)에 문제가 있습니다
  CRE_GUARD: 모르는 태그 '비행행'
```

`Cards/Core.luau` 는 그 표를 엔진이 읽는 모양으로 펴는 변환기다 — 카드가 늘어도
그 파일은 그대로이므로, 수치를 만질 때 열 일이 없다.

### 밸런스 계측 (테스트가 아니다)

```powershell
lune run tests/balance.luau              # 60판
lune run tests/balance.luau -- --games 200
```

AI 둘이 스타터 덱으로 여러 판 두게 하고 판 길이 · 덱 사용량 · 손패 · 멀리건 비율을 뽑는다.
**통과/실패가 없다** — 숫자를 보고 사람이 판단한다. 그래서 CI 에 넣지 않았다.
덱이나 카드를 건드릴 때 전후를 같은 자로 재려고 만들었다.

### 클라이언트 코드는 어떻게 테스트하나

`src/client` 는 `game:GetService` 를 쓰므로 Lune 에서 그냥은 안 돌아간다. 두 갈래로 본다.

| 무엇 | 어디서 | 어떻게 |
|---|---|---|
| 클릭 → 판정 (`Controller`) | `tests/specs/controller.luau` | `RobloxEnv.newLoader()` 가 `src/shared` 와 `src/client` 를 **한 캐시로** 마운트하고, `game:GetService("ReplicatedStorage"):WaitForChild("Shared")` 만 흉내낸다. 서버가 보낼 스냅샷(`viewFor` → `packView`)을 그대로 태워 하이라이트를 확인한다 |
| 화면 (`Battle`·`Home`) | `tests/smoke.luau` | 진짜 인스턴스 트리 위에서 버튼을 눌러보고 텍스트를 읽는다 |

캐시를 나누면 안 된다 — `src/client` 가 룰을 다시 로드하면 `Cards.load()` 가 한쪽 사본에만
남아 클라이언트 쪽 `Registry.mustGet` 이 "등록되지 않은 카드" 로 죽는다.
Roblox 에서는 `ReplicatedStorage` 의 같은 ModuleScript 를 공유하므로, 한 벌만 있어야 실제와 같다.

### 왜 `.ps1` 과 `.sh` 가 둘 다 있나

검사 목록은 `scripts/ci.sh` **하나뿐**이다. 사람도, 커밋 훅도, GitHub Actions 도 그걸
돌린다 — 목록이 두 곳에 있으면 반드시 어긋난다.

`.ps1` 은 그걸 부르기만 하는 껍데기다. 윈도우 PowerShell 에는 `sh` 가 없어서
(Git 이 `sh.exe` 를 깔아두지만 PATH 에 올려주지 않는다) `sh scripts/ci.sh` 가
"명령을 찾을 수 없음" 으로 끝나기 때문이다. `.ps1` 이 `sh.exe` 를 찾아서 넘긴다.

`studio.ps1` 은 한 가지를 더 한다 — `.rbxlx` 파일 연결이 없는 환경에서는
`start build.rbxlx` 도 실패하므로, Studio 실행 파일을 직접 찾아 넘긴다.
(Git Bash 에서 작업한다면 `.sh` 쪽을 그대로 써도 된다)

### 로컬 (원격 없이도 된다)

```powershell
git config core.hooksPath .githooks   # 이 저장소에서 한 번만
```

이후 **커밋할 때마다** `.githooks/pre-commit` 이 로컬 CI 를 돌린다.
통과하면 아무 말 없이 커밋되고, 실패하면 커밋이 막히면서 실패한 검사만 출력된다.

```powershell
scripts\ci.cmd            # 직접 돌려보기 (결과 전부 출력)
git commit --no-verify    # 한 번만 건너뛰기
git config --unset core.hooksPath   # 훅 끄기
```

훅을 `.git/hooks/` 가 아니라 `.githooks/` 에 두고 `core.hooksPath` 로 가리키는 이유:
`.git/` 안은 버전 관리가 안 된다. 이렇게 두면 훅 자체가 커밋되어 남는다.
**다른 컴퓨터에서 클론했을 때도 위 한 줄만 치면 그대로 켜진다** — 학교 컴퓨터처럼
새로 받은 환경에서 가장 먼저 할 일이다.

### 문서가 코드를 따라오게 하는 것

같은 pre-commit 훅이 로컬 CI 앞에 `scripts/docs-sync.sh` 를 한 번 돌린다.
**코드는 바뀌었는데 짝이 되는 문서는 그대로면 알려준다.** 어느 코드가 어느 문서와
짝인지는 [문서 목차](README.md) 의 표에 있다.

```
! src/shared/Rules/Config.luau 를 고쳤는데 docs/rules.md docs/open-questions.md 는 그대로입니다.
  문서가 필요 없는 수정이면 그냥 커밋하세요. 이 검사는 막지 않습니다.
```

**이것만 막지 않는다.** 오타 고침처럼 문서가 필요 없는 수정도 있는데 그때마다 커밋이
막히면 사람이 `--no-verify` 를 습관으로 쓰게 되고, 그러면 훅 전체가 무의미해진다.

정답이 분명한 쪽 — 문서가 가리키는 파일 경로가 실제로 있는가, 문서끼리의 링크가
살아 있는가, 목차에서 빠진 문서가 있는가 — 은 `lune run tests/docs.luau` 가 보고
**CI 를 빨간불로 만든다.** 문서가 틀리는 방식은 대개 "파일을 옮겼는데 문서는 옛 경로를
계속 가리킨다" 이고, 그건 사람이 판단할 일이 아니라 기계가 확인할 일이다.

`.claude/settings.json` 에도 같은 스크립트를 걸어 뒀다 — Claude Code 로 작업하면
파일을 고칠 때마다 같은 경고가 뜬다. (커밋까지 가지 않고 그 자리에서 보인다)

한계 하나 — 검사 대상은 **작업 트리**다. 일부 파일만 stage 한 커밋이면 실제 커밋 내용과
다를 수 있어서, 그럴 때는 훅이 먼저 경고한다. (정확히 하려면 stash 를 써야 하는데
훅이 실패할 때 작업물을 잃을 위험이 생겨서 경고 쪽을 택했다)

### GitHub (푸시하면 자동)

`.github/workflows/ci.yml` 이 같은 순서를 돌린다. 다른 점은 둘:

- **툴체인**을 `aftman.toml` 그대로 설치한다 → 로컬과 CI 가 같은 rojo/lune 을 쓴다
- 나온 `build.rbxlx` 를 **아티팩트로 올린다** → 받아서 더블클릭하면 그 커밋의 게임이 열린다

서식 검사(StyLua)는 별도 잡이고 `continue-on-error: true` 다. 아래 이유로 앞으로도 그렇다.

### 왜 자동 정렬을 껐나

`stylua` 는 줄 길이를 **바이트로 센다.** 한글은 글자당 3바이트라, 화면에서 60자쯤 되는
줄을 180바이트로 보고 쪼갠다:

```luau
-- 손으로 맞춘 것
return false, "지상 생물은 '비행' 생물을 공격할 수 없습니다 ('비행' 또는 '원거리' 필요)"

-- stylua(폭 110)가 바꾸려는 것
return false,
	"지상 생물은 '비행' 생물을 공격할 수 없습니다 ('비행' 또는 '원거리' 필요)"
```

폭을 넓히면 이번엔 반대로, 여러 줄로 나눠 쓴 조건문을 한 줄로 합친다. 실제로 재보면
어느 값도 0 이 되지 않는다:

| `column_width` | 어긋나는 파일 |
|---|---|
| 110 | 32개 |
| **140 (현재)** | **19개** |
| 200 | 24개 |

이 저장소는 한글 **표시 폭** 기준으로 손으로 맞춰 왔고 stylua 는 그 기준을 모르므로,
`.vscode/settings.json` 에서 luau 의 `editor.formatOnSave` 를 껐다. 포매터 지정은
남겨뒀으니 필요하면 `Shift+Alt+F` 로 그 파일만 정렬할 수 있고,
`stylua src tests play.luau` 로 전체를 한 번에 정렬할 수도 있다 — 다만 그러면
한글 문자열이 여기저기 쪼개진다.

### 검사 셋이 각자 메우는 구멍

| | 무엇을 아는가 | 무엇을 모르는가 |
|---|---|---|
| `check.luau` | 전부 컴파일된다 | 돌려보면 죽는지 |
| `run.luau` | 룰이 맞다 (`src/shared` 를 실제로 실행) | 서버·클라이언트가 도는지 |
| `smoke.luau` | 서버·클라이언트가 실제로 돈다 | 화면이 예쁜지 |

`run.luau` 가 `src/shared` 만 로드하는 이유는 서버/클라이언트 코드가 Roblox API 를 쓰기
때문이다. 그래서 오랫동안 `src/server` · `src/client` 는 **아무도 실행해본 적 없는 상태로**
커밋됐다 — 문법이 맞아도 `nil` 인덱싱, 잘못된 require 경로, 없는 Enum 항목, 오타난 속성은
Studio 를 켜서 그 화면이 뜰 때까지 아무도 모른다. `smoke.luau` 가 그 구멍을 메운다.

---

## 스모크 테스트 — Studio 를 켜기 전에

```powershell
lune run tests/smoke.luau
```

`tests/lib/Roblox*` 가 Roblox 표면(Instance · 서비스 · 데이터타입 · task)을 흉내내고,
그 위에서 **`src/server` 와 `src/client` 를 진짜로 실행한다.** 서버를 부팅하고, 사람을
접속시키고, **화면의 버튼을 눌러서** 매칭과 대전을 시킨다. 판정도 화면을 읽어서 한다 —
내부 변수를 들여다보지 않으므로, 통과했다는 말은 "사람이 그 버튼을 눌렀을 때 그 화면이
나온다" 는 뜻이다.

```lua
Screen.click(Screen.findButton(kim.PlayerGui, "빠른 대전"))
world:advance(6)                       -- 6초가 흘렀다 (가상 시계)
t:eq(panelName(kim, "MyPanel"), "Kim") -- Kim 화면의 아래칸은 Kim 이어야 한다
```

확인하는 시나리오:

| | 내용 |
|---|---|
| 로비 | 시작 화면 · 큐 등록 · 취소 · 혼자면 매칭 안 됨 |
| AI 연습 | 판 시작 · **여러 턴 진행** · 항복 · 로비 복귀 |
| 같은 서버 매칭 | 두 사람 매칭 · **각자 자기가 아래칸** · 선공이 한 명 · 이탈 몰수 |
| 크로스서버 매칭 | 서로 다른 서버 → 예약 서버에서 만남 · 좌석/시드 일치 · 취소 반영 |
| 화면 배율 | 720 · 900 · 1440 창에서 UI 배율이 맞게 잡히는지 |

**크로스서버 시나리오가 특히 중요하다.** 그 경로는 Studio 에서 한 줄도 실행되지 않아서,
이 테스트가 없으면 게시하기 전까지 검증할 방법이 아예 없다.

### 엄격하게 흉내낸다

느슨한 흉내는 "테스트는 초록불인데 Studio 는 빨간 줄" 을 만든다. 그래서 모르는 것은
조용히 넘기지 않고 그 자리에서 실패시킨다.

```
Instance.new("TextLable")        → 없는 클래스입니다
label.TextColour3 = ...          → TextLabel 에는 그 속성이 없습니다
Enum.TextXAlignment.Centre       → 없는 항목입니다
game:GetService("DataStore")     → 모르는 서비스입니다
```

속성 표는 `tests/lib/Roblox/Instance.luau` 에 손으로 적혀 있다. 새 속성을 쓰기 시작하면
거기에도 한 줄 추가해야 하는데, 그 한 줄이 "Studio 를 켜서 그 화면이 뜰 때까지 아무도
모르는 오타" 를 없앤다.

### 흉내내지 않는 것

- 픽셀 레이아웃 — `UIListLayout` 이 실제로 정렬하지 않는다. **화면이 예쁜지는 모른다**
- 복제 지연 — `FireClient` 가 즉시 도착한다
- 실제 MemoryStore / MessagingService / 텔레포트 — 동작을 흉내낼 뿐 실제 응답이 아니다
- 실제 시간 — 시계는 `world:advance` 로만 흐른다

그래서 스모크 테스트가 통과해도 **Studio 를 한 번은 켜봐야 한다.** 다만 켰을 때
출력창이 빨갛지 않다는 것은 미리 안다.
