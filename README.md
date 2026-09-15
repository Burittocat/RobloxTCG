# RobloxTCG

**로블록스로 만든 1:1 트레이딩 카드 게임.** 매직 더 개더링 계열의 규칙(코스트 · 스택 ·
즉시시전 대응)을 로블록스 위에 올렸다. 언어는 Luau, 소스는 전부 텍스트 파일로 두고
Rojo 로 Studio 에 밀어넣는다. Studio 없이 도는 테스트 152개가 CI 에서 돈다.

로비는 없다. 접속하면 버튼 넷이 뜬다 — **빠른 대전 · 튜토리얼 · AI 연습 · 덱 편집.**
빠른 대전은 서버를 넘나드는 큐에 서서 사람을 찾는다 (마스터듀얼 · MTG 아레나 방식).

## 게임 시스템

- **자원이 카드다.** 60장 덱에 코스트 카드를 원하는 만큼 섞고, 턴당 1장씩 필드에 깔아 늘린다.
- **턴은 3페이즈.** 메인(소환·마법) → 공격준비(공격자 선언) → 수비준비(방어 배정). 전투는 동시 해결.
- **태그 5종.** 신속 · 비행 · 도발 · 원거리 · 즉시시전. 태그끼리 물고 물리는 게 전투의 전부다.
- **스택이 있다.** 낸 카드는 바로 터지지 않고 쌓인다 — 상대는 즉시시전으로 무효화하거나 덱으로 되돌린다.
- **판 시작 전 멀리건 1회 무료.** 라이프 30, 빈 덱을 뽑으면 패배.

## 화면

<!--
  스크린샷을 docs/media/ 에 넣고 아래 주석을 풀면 바로 뜬다. 찍는 법은 docs/media/README.md
  ![전투](docs/media/battle.png)
  ![시작 화면](docs/media/home.png)  ![덱 편집](docs/media/deck.png)
-->

_스크린샷 준비 중 — 넣는 자리와 방법은 [`docs/media/`](docs/media/) 에 적어 뒀다._

## 해보기

```sh
git clone https://github.com/Burittocat/RobloxTCG.git
cd RobloxTCG && aftman install     # rojo · lune
rojo build --output build.rbxlx    # 이 파일을 Studio 로 열면 바로 플레이
```

터미널에서 AI 와 한 판 두려면 `lune run play.luau`. Studio 연동·개발 환경은
[실행하고 개발하기](docs/getting-started.md) 에 있다.

## 문서

전부 [`docs/`](docs/) 에. 자주 여는 것 셋:

- [구현된 룰](docs/rules.md) — 턴 구조 · 태그 · 코스트 · 스택
- [코드 구조](docs/architecture.md) — 폴더 분담 · 서버/클라 경계
- [★ 확정이 필요한 항목](docs/open-questions.md) — 기획서에 없어 임의로 정한 것들

## 상태

룰 엔진 · PvE AI · 전투 UI · 튜토리얼 · 덱 편집 · 빠른 대전 매칭까지 동작한다.
남은 큰 것은 **PvE 캠페인**과 **BM(카드팩 · 코스메틱)** — [다음 단계](docs/roadmap.md).
