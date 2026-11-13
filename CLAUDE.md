# Claude 작업 메모

Claude Code 가 이 저장소에서 시작할 때 자동으로 읽는 파일이다. **어느 컴퓨터에서든 같은 기억으로
이어서 작업하려고** git 에 둔다. 사람이 읽는 설명서는 [`docs/`](docs/README.md) 에 있고, 여기에는
"지금 어디까지 왔나 · 어떻게 일하나" 만 적는다. 작업이 끝날 때마다 고쳐서 같이 커밋한다.

---

## 일하는 방식 (사용자가 정한 것)

- **개발한 내용과 이 메모를 계속 git 에 커밋한다.** 기능 하나가 끝나면 코드 · 문서 · 이 파일을
  같이 커밋하고 푸시한다. 로컬에만 두면 다른 컴퓨터에서 이어갈 수 없다
- **브랜치 없이 main 에 바로 커밋 · 푸시한다** (2026-11-12 사용자 지시 — 예전의 "브랜치 + PR" 을
  바꿨다). `.github/workflows/ci.yml` 은 main 푸시에서도 돌아서 룰 테스트 · 스모크 · 문서 검사 ·
  플레이스 빌드를 해준다. 푸시한 뒤 CI 결과를 확인하고, 깨졌으면 main 에서 바로 고친다
- 집 밖(Studio 없음)에서는 **기능 구현 위주.** 화면 확인 · 배포는 집에서 사용자가 한다
- CI 의 **"코드 서식 (권고)" 잡은 원래 빨간불**이다(stylua 가 한글을 바이트로 센다). 무시한다.
  봐야 하는 것은 "룰 엔진 · 빌드" 잡이다
- 커밋 작성자는 기존과 같게: `csh98 <johnkramer1225@gmail.com>` (저장소 로컬 설정)
- 기획서에 없는 수치를 정하면 [`docs/open-questions.md`](docs/open-questions.md) 의 ★ 표에 올린다

## 컴퓨터별 메모

**밖에서 쓰는 Windows (2026-11-12)**
- git 은 PATH 에 없다 — `C:\Users\USER\PortableGit\cmd\git.exe` (Portable Git 2.56.0)
- 푸시는 `git -c credential.helper=manager push`. 로그인은 저장돼 있다.
  Claude 세션에서 처음 푸시할 때는 `$env:GCM_INTERACTIVE='always'` 를 줘야 로그인 창이 뜬다
- lune · rojo 없음(`scripts\bootstrap.cmd` 실행이 자동 권한 검사에 막혔다) → 검증은 PR CI 로 한다
- 저장소 위치: `C:\Users\USER\RobloxTCG-repo`

**또 다른 Windows (`C:\Users\USER\RobloxTCG`) — 2026-11-13 다시 세팅**
- 11-12 에 깔았던 git · gh 가 없어져 있었다. 2026-11-13 에 **git 만** winget 으로 다시 깔았다
  (`winget install --id Git.Git -e`). Claude 세션의 PowerShell 은 PATH 를 못 이어받으므로
  명령마다 `$env:Path = "C:\Users\USER\RobloxTCG\.tools;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;" + $env:Path`
- 로그인은 gh 없이 **Git Credential Manager**: `$env:GCM_INTERACTIVE='always'; git credential-manager github login`
  → 브라우저 창. `git credential-manager github list` 가 `Burittocat` 을 보이면 된다
- `powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1` 은 이번엔 됐다 → lune · rojo 가 `.tools\` 에,
  훅도 켜져 있다(`core.hooksPath .githooks`). **로컬 CI(`sh scripts/ci.sh`)가 돈다**

## 지금 어디까지 왔나

| 날짜 | 무엇 | 어디 |
|---|---|---|
| ~2026-09 | 룰 엔진 · AI · 전투 UI · 튜토리얼 · 덱 편집 · 빠른 대전 · 캠페인 | `docs/roadmap.md` |
| 2026-11-12 | **카드팩 + 컬렉션** — 가진 카드로만 덱, 100 골드 5장 팩(희귀 1 확정), 중복 환급 | [`docs/collection.md`](docs/collection.md) |
| 2026-11-12 | **PvP 승리 보상** — 25 골드, 하루 4판, 4턴 미만 판 제외 | `docs/collection.md` 의 "골드는 어디서 버나" |
| 2026-11-12 | **Robux 로 팩 사기** — DevProduct, 영수증 중복 방지(컬렉션에 receipts 기록) | `docs/collection.md` 의 "Robux 로 팩 사기" |
| 2026-11-12 | **꾸미기 — 카드 테두리** 6종(기본 + 150G 셋 + 250G 둘). 컬렉션 저장값의 `cosmetics`, 스냅샷 `frames` 로 상대에게도 보인다 | `docs/collection.md` 의 "꾸미기" |
| 2026-11-12 | **꾸미기 — 카드 뒷면** 5종. 상대 화면의 내 손패에 보인다. Cosmetics 를 "종류" 로 일반화 | `docs/collection.md` 의 "종류를 늘리려면" |
| 2026-11-12 | **꾸밈 등급** 일반 · 희귀 · 레어 · 에픽 · 고져스(사용자 지정). 가격은 등급이 정한다(0/100/150/250/400) | `docs/collection.md` 의 "등급" |
| 2026-11-12 | **랭크 · MMR 매칭 · 프로필** — 보이는 랭크 점수(티어 6단계) + 숨은 MMR(Elo). 짧은 판은 이긴 쪽 무기록 · 진 쪽 감점. 프로필 화면(보기만) | [`docs/rank.md`](docs/rank.md) |
| 2026-11-13 | **골드 표기 다듬기** — 금색 동전(채운 원 + 어두운 G) · 칩 바탕/테두리 · 프로필의 골드만 금색. 세 화면이 베껴 쓰던 purse 코드를 `Widgets.goldChip` 으로 모았다 | `src/client/UI/Widgets.luau` |
| 2026-11-12 | **순위표 · 남의 프로필** — OrderedDataStore 위 50명, 이름 누르면 그 사람 프로필(덱 · 골드 · MMR 숨김). 하네스에 OrderedDataStore · GetNameFromUserIdAsync 추가 | `docs/rank.md` 의 "순위표" |
| 2026-11-13 | **밸런스 — 방패병 4코 1/6 → 2/4.** 늘어진 판(40턴+) 1000판 중 99 → 20, 덱아웃 17 → 0. `tests/balance.luau` 에 분포 · 선공 승률 · 끝난 전장 · `--stage N` 추가 | `docs/roadmap.md` 의 "밸런스" |
| 2026-11-13 | **캠페인 난이도 곡선** — 3번 "방벽 수비대" 거석상 4 → 2 · 라이프 30 → 25. 도전자 승률 84 · 76 · 70 · 68 · 54% 로 순서대로 | `docs/campaign.md` 의 "난이도 곡선" |
| 2026-11-13 | **결과 화면의 상대 프로필** — PvP 결과 상자 셋째 버튼. 남의 프로필 조립을 `PublicProfile` 로 모아 Lobby · Arena 가 같이 쓴다. 전투 화면 위에 겹치고(`backTo = "battle"`) 서버 화면 상태는 그대로 | `docs/rank.md` 의 "결과 화면의 상대 프로필" |

> **순위표 커밋(6cd5c26)의 CI 는 실제로 빨간불이었고, 2026-11-13 집에서 고쳤다** — 스모크
> 둘(`순위표가 점수 순으로…`, `이름을 누르면 그 사람의 프로필…`)이 실패했다. 원인은 기능이
> 아니라 **테스트 하네스**였다(아래 함정 첫 줄). 고친 뒤 로컬 CI 전부 통과(스모크 108개).

- **PR #1 을 main 에 머지했다**(d6dd09a, 2026-11-12). 커밋 셋 다 CI 통과.
  사용자 요청으로 **Studio 화면 확인 전에** 머지했다 — 집에서 확인하다 문제가 나오면 main 에서 고친다
- 루트 `README.md` 의 "테스트 272개" 는 이번에 늘어난 수를 아직 반영하지 않았다

## 다음 할 일

1. **사용자 몫: Robux 상품 만들기** — 크리에이터 대시보드 → Developer Products. 나온 ID 를
   `src/shared/Products.luau` 의 `robuxPack` 에 넣으면 카드팩 화면에 버튼이 뜬다. 가격도 그때 정한다
0. **다음은 전투 화면(게임 플레이 UI) 다듬기** — 2026-11-13 사용자: "지금 너무 허접해", 시즌 · 티어 보상보다 먼저.
   사용자가 **집에서 Studio 로 전투 화면 스크린샷**(내 차례 · 공격/방어 중 · 결과 화면)을 찍어 오기로 했다.
   스크린샷을 받으면 직접 보고 겉모습(색 · 간격 · 글꼴 · 카드 생김새)부터 짚는다.
   스크린샷 없이 시작하면 추천은 **움직임** — `Battle:render` 를 통째 다시 그리기에서 바뀐 것만 고치는
   방식으로 바꾸고 카드 이동 연출을 붙인다(`docs/roadmap.md` "연출"). 구조 작업이라 테스트로 확인된다.
   그 밖의 약점: 카드 그림 없음(`CardView`) · 모바일/세로 화면 · 무덤 열람 · 카드 확대 보기
2. 후보(Studio 없이 되는 것): 시즌 · 티어 보상 · 재접속 · 캠페인 스테이지 추가 · 카드 추가.
   **큐 인원 표시는 보류**(2026-11-13 사용자 결정) — 당장 다인 플레이 모드가 없고, 사람이 적을 때
   "0명 대기" 가 오히려 큐를 비운다. 동시 접속이 늘면 다시 본다(별도 카운터 필요 — `docs/roadmap.md`)
   (집에서: Studio 로 시작 화면 오른쪽 위 [순위표][프로필] 위치 · 프로필 · 순위표 배치도 본다.
   **결과 상자의 버튼 셋**(128px 로 좁혔다)이 글자를 자르지 않는지도)
3. **코스메틱 나머지** — 이펙트(소환 연출). 연출이라 **집에서 Studio 로** 하는 편이 낫다.
   "스킨" 은 카드 앞면 바탕이 종류 정보라 덮지 않고 **카드 뒷면**으로 했다(2026-11-12)
3. 집에서: Studio 로 카드팩 화면 · 덱 편집 "덱/가진 것" 표시 · PvP 보상 · Robux 테스트 구매 확인 ·
   (2026-11-13 에 **머리의 골드 표기는 눈으로 확인받았다** — 세 화면 머리 · 프로필. 나머지는 아직) ·
   **꾸미기 화면과 테두리 색**(특히 서리 · 물결이 카드 바탕 위에서 읽히는지, 하이라이트와 헷갈리지 않는지) ·
   **카드 뒷면 무늬 글자**(● ◆ ▲ ★ 가 Gotham 에서 네모로 안 나오는지, 26px 칸에서 보이는지)

## 이번에 배운 함정

- 로블록스는 글자를 **글리프가 아니라 줄 상자(line box)로** 가운데 맞춘다. 그 상자에는 `g` · `y`
  처럼 밑으로 내려가는 글자 자리가 들어 있어서, 대문자 하나(동전의 "G")를 가운데 맞추면
  아래로 처져 보인다 — 1px 올려서 눈으로 맞췄다(`Widgets.goldIcon`)
- 하네스의 `GetDataStore` · `GetOrderedDataStore` 는 표를 **부를 때마다 이름으로 찾아야** 한다.
  참조를 미리 잡아두면 테스트가 `world.orderedStores[이름] = { ... }` 로 표를 갈아치웠을 때
  서버 쪽 객체만 옛 표를 들고 있어 **저장값이 통째로 빈 것처럼 보인다**(순위표가 0줄로 떴다).
  빈 표를 **즉시 만들어 두는 것도 같이** 지켜야 한다 — 테스트가 아무 일도 일어나기 전에
  `world.dataStores[...]` 를 들여다본다(게으르게 바꿨다가 카드팩 테스트 5개가 깨졌다)
- `Campaign.applyClear` 처럼 진행도를 `{ cleared, gold }` 로 **새로 만들면** 나중에 붙인 칸이 지워진다.
  진행도는 통째로 복사한 뒤 고친다(`copy`)
- Luau 에서 `f(g(), x)` 처럼 다중 반환 호출이 마지막 인자가 아니면 첫 값만 넘어간다 —
  `t:denied(validate(v), nil, "...")` 는 사유를 잃는다. 지역 변수로 받아서 넘긴다
- PowerShell 에서 `git commit -F -` 에 here-string 을 파이프 없이 넘기면 경로로 해석된다.
  메시지는 파일로 써서 `-F <파일>`. **`Set-Content -Encoding utf8` 로 쓰지 않는다** — PS 5.1 은 BOM 을
  붙여서 커밋 제목 앞에 보이지 않는 문자가 들어간다(d348df6). Write 도구나 BOM 없는 UTF8Encoding 으로 쓴다
- 밸런스 실험으로 `Sheet.luau` 를 스크립트로 바꿨다 되돌릴 때는 `[IO.File]::WriteAllText(..., New-Object Text.UTF8Encoding $false)` —
  역시 BOM 을 안 넣으려고
- 새 Roblox 서비스나 Enum 을 쓰면 **테스트 하네스에도 추가해야** 한다
  (`tests/lib/Roblox/init.luau` 의 `Server:service`, `tests/lib/Roblox/Datatypes.luau` 의 ENUMS).
  안 하면 스모크 테스트가 부팅에서 전부 죽는다. MarketplaceService 가 그랬다
- 컬렉션에 칸을 늘리면 `Collection.copy` 에만 더하면 된다(2026-11-12 부터 새 컬렉션은 전부
  copy 를 거친다). copy 에 빠뜨리면 조용히 지워진다(receipts · cosmetics 를 지키는 테스트가 있다)
- `script.Parent` 로 다른 모듈을 require 하는 shared 모듈은 스모크(`tests/smoke.luau`)가 Lune 의
  `require` 로 바로 못 읽는다. 테스트가 값을 맞춰 봐야 하면 순수 테이블을 따로 뺀다
  (`Products.luau`, `Cosmetics/Frames.luau`)
- 스모크의 `isLit` 은 테두리 **두께 4 이상**을 "켜진 카드" 로 본다. 카드 테두리를 건드릴 때 4 를 넘기지 않는다
- 하네스의 `addPlayer` 는 PlayerAdded 를 **동기로** 쏜다. 테스트는 addPlayer 직후에 저장소 값을 넣으므로,
  접속 처리에서 저장소를 바로 읽으면 빈 값이 캐시된다 → 읽기는 `task.wait()` 한 박자 뒤로 미룬다(Lobby:onPlayerAdded)
- 전투 화면 알림 칸(`Battle:showToast`)은 **하나**다. 한 사람에게 알림을 연달아 보내면 뒤의 것이 앞의 것을 덮는다 → 묶어서 한 번에
- `Rank` 는 `Campaign` 을 require 한다. Campaign 쪽에서 Rank 를 부르면 순환이다 — 진행도 칸 검사는 Campaign 목록에 둔다
