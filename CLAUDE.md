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

**또 다른 Windows (2026-11-12, `C:\Users\USER\RobloxTCG`)**
- git · GitHub CLI 는 winget 으로 설치했다(PATH 에 있다. 새 창이 아니면
  `$env:Path` 를 Machine+User 로 다시 읽어야 보인다)
- 로그인은 `gh auth login --web` (일회용 코드 → github.com/login/device). Claude 세션에서
  창을 띄우면 코드가 안 보이므로, 출력을 파일로 받아 코드를 읽어 주는 편이 낫다
- 여기서도 `scripts\bootstrap.cmd` 가 자동 권한 검사에 막혔다 → 훅 없음 · lune 없음 → 검증은 main 푸시 CI

## 지금 어디까지 왔나

| 날짜 | 무엇 | 어디 |
|---|---|---|
| ~2026-09 | 룰 엔진 · AI · 전투 UI · 튜토리얼 · 덱 편집 · 빠른 대전 · 캠페인 | `docs/roadmap.md` |
| 2026-11-12 | **카드팩 + 컬렉션** — 가진 카드로만 덱, 100 골드 5장 팩(희귀 1 확정), 중복 환급 | [`docs/collection.md`](docs/collection.md) |
| 2026-11-12 | **PvP 승리 보상** — 25 골드, 하루 4판, 4턴 미만 판 제외 | `docs/collection.md` 의 "골드는 어디서 버나" |
| 2026-11-12 | **Robux 로 팩 사기** — DevProduct, 영수증 중복 방지(컬렉션에 receipts 기록) | `docs/collection.md` 의 "Robux 로 팩 사기" |
| 2026-11-12 | **꾸미기 — 카드 테두리** 6종(기본 + 150G 셋 + 250G 둘). 컬렉션 저장값의 `cosmetics`, 스냅샷 `frames` 로 상대에게도 보인다 | `docs/collection.md` 의 "꾸미기" |

- **PR #1 을 main 에 머지했다**(d6dd09a, 2026-11-12). 커밋 셋 다 CI 통과.
  사용자 요청으로 **Studio 화면 확인 전에** 머지했다 — 집에서 확인하다 문제가 나오면 main 에서 고친다
- 루트 `README.md` 의 "테스트 272개" 는 이번에 늘어난 수를 아직 반영하지 않았다

## 다음 할 일

1. **사용자 몫: Robux 상품 만들기** — 크리에이터 대시보드 → Developer Products. 나온 ID 를
   `src/shared/Products.luau` 의 `robuxPack` 에 넣으면 카드팩 화면에 버튼이 뜬다. 가격도 그때 정한다
2. **코스메틱 나머지** — 스킨(카드 바탕) · 이펙트. 테두리와 같은 `cosmetics` 칸 · 같은 길(좌석 → 스냅샷)로
3. 집에서: Studio 로 카드팩 화면 · 덱 편집 "덱/가진 것" 표시 · PvP 보상 · Robux 테스트 구매 확인 ·
   **꾸미기 화면과 테두리 색**(특히 서리 · 물결이 카드 바탕 위에서 읽히는지, 하이라이트와 헷갈리지 않는지)

## 이번에 배운 함정

- `Campaign.applyClear` 처럼 진행도를 `{ cleared, gold }` 로 **새로 만들면** 나중에 붙인 칸이 지워진다.
  진행도는 통째로 복사한 뒤 고친다(`copy`)
- Luau 에서 `f(g(), x)` 처럼 다중 반환 호출이 마지막 인자가 아니면 첫 값만 넘어간다 —
  `t:denied(validate(v), nil, "...")` 는 사유를 잃는다. 지역 변수로 받아서 넘긴다
- PowerShell 에서 `git commit -F -` 에 here-string 을 파이프 없이 넘기면 경로로 해석된다.
  메시지는 파일로 써서 `-F <파일>`
- 새 Roblox 서비스나 Enum 을 쓰면 **테스트 하네스에도 추가해야** 한다
  (`tests/lib/Roblox/init.luau` 의 `Server:service`, `tests/lib/Roblox/Datatypes.luau` 의 ENUMS).
  안 하면 스모크 테스트가 부팅에서 전부 죽는다. MarketplaceService 가 그랬다
- 컬렉션에 칸을 늘리면 `Collection.copy` 에만 더하면 된다(2026-11-12 부터 새 컬렉션은 전부
  copy 를 거친다). copy 에 빠뜨리면 조용히 지워진다(receipts · cosmetics 를 지키는 테스트가 있다)
- `script.Parent` 로 다른 모듈을 require 하는 shared 모듈은 스모크(`tests/smoke.luau`)가 Lune 의
  `require` 로 바로 못 읽는다. 테스트가 값을 맞춰 봐야 하면 순수 테이블을 따로 뺀다
  (`Products.luau`, `Cosmetics/Frames.luau`)
- 스모크의 `isLit` 은 테두리 **두께 4 이상**을 "켜진 카드" 로 본다. 카드 테두리를 건드릴 때 4 를 넘기지 않는다
