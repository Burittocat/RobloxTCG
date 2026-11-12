# Claude 작업 메모

Claude Code 가 이 저장소에서 시작할 때 자동으로 읽는 파일이다. **어느 컴퓨터에서든 같은 기억으로
이어서 작업하려고** git 에 둔다. 사람이 읽는 설명서는 [`docs/`](docs/README.md) 에 있고, 여기에는
"지금 어디까지 왔나 · 어떻게 일하나" 만 적는다. 작업이 끝날 때마다 고쳐서 같이 커밋한다.

---

## 일하는 방식 (사용자가 정한 것)

- **개발한 내용과 이 메모를 계속 git 에 커밋한다.** 기능 하나가 끝나면 코드 · 문서 · 이 파일을
  같이 커밋하고 푸시한다. 로컬에만 두면 다른 컴퓨터에서 이어갈 수 없다
- **브랜치에 올리고 PR 로 CI 를 돌린다.** `.github/workflows/ci.yml` 은 PR 과 main 푸시에서 돈다.
  Studio 를 못 여는 곳에서도 PR CI 가 룰 테스트 · 스모크 · 문서 검사 · 플레이스 빌드를 다 해준다
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

## 지금 어디까지 왔나

| 날짜 | 무엇 | 어디 |
|---|---|---|
| ~2026-09 | 룰 엔진 · AI · 전투 UI · 튜토리얼 · 덱 편집 · 빠른 대전 · 캠페인 | `docs/roadmap.md` |
| 2026-11-12 | **카드팩 + 컬렉션** — 가진 카드로만 덱, 100 골드 5장 팩(희귀 1 확정), 중복 환급 | [`docs/collection.md`](docs/collection.md) |
| 2026-11-12 | **PvP 승리 보상** — 25 골드, 하루 4판, 4턴 미만 판 제외 | `docs/collection.md` 의 "골드는 어디서 버나" |

- 브랜치 `feature/card-packs` → **PR #1** (https://github.com/Burittocat/RobloxTCG/pull/1).
  커밋 92c1d9e 의 CI "룰 엔진 · 빌드" 통과. 아직 main 에 안 합쳤다 — Studio 에서 화면 확인 후 머지
- 루트 `README.md` 의 "테스트 272개" 는 이번에 늘어난 수를 아직 반영하지 않았다

## 다음 할 일

1. **Robux 로 팩 사기** — DevProduct. 상품 ID 가 비어 있으면 버튼을 끈다(`Theme.image.gold` 와 같은 태도).
   ID 는 크리에이터 대시보드에서 만들어 나중에 넣는다
2. **코스메틱** — 테두리 · 스킨 · 이펙트. 카드 데이터와 분리된 레이어로
3. 집에서: Studio 로 카드팩 화면 · 덱 편집 "덱/가진 것" 표시 확인 → PR #1 머지

## 이번에 배운 함정

- `Campaign.applyClear` 처럼 진행도를 `{ cleared, gold }` 로 **새로 만들면** 나중에 붙인 칸이 지워진다.
  진행도는 통째로 복사한 뒤 고친다(`copy`)
- Luau 에서 `f(g(), x)` 처럼 다중 반환 호출이 마지막 인자가 아니면 첫 값만 넘어간다 —
  `t:denied(validate(v), nil, "...")` 는 사유를 잃는다. 지역 변수로 받아서 넘긴다
- PowerShell 에서 `git commit -F -` 에 here-string 을 파이프 없이 넘기면 경로로 해석된다.
  메시지는 파일로 써서 `-F <파일>`
