# 문서

루트 `README.md` 는 "이게 뭔지" 만 말한다. 자세한 것은 전부 여기 있다.

| 문서 | 무엇이 들어 있나 |
|---|---|
| [새 컴퓨터에서 처음부터](new-machine.md) | 아무것도 없는 환경에서 개발 재개까지 · 막혔을 때 증상별 처방 |
| [실행하고 개발하기](getting-started.md) | Studio 에서 켜기 · 터미널에서 한 판 · VS Code 세팅 · Rojo |
| [구현된 룰](rules.md) | 턴 구조 · 태그 5종 · 코스트 · 멀리건 · 스택 |
| [코드 구조](architecture.md) | 폴더가 무엇을 맡나 · 서버/클라 분담 · 화면이 보고 그리는 것 |
| [빠른 대전 매칭](matchmaking.md) | 크로스서버 큐 · 예약 서버 · 좌석 · 취소와 만료 |
| [덱 편집과 저장](decks.md) | 덱 빌더 · DataStore · 대전 서버가 덱을 읽는 경로 |
| [튜토리얼](tutorial.md) | 코치가 붙는 한 판 · 왜 대본이 아니라 조건인가 |
| [테스트와 CI](testing.md) | 로컬 CI · GitHub Actions · 가짜 Roblox 스모크 테스트 |
| [★ 확정이 필요한 항목](open-questions.md) | 기획서에 없어서 임의로 정한 것들 |
| [다음 단계](roadmap.md) | 끝난 것 · 남은 것 · 지금 보이는 구멍 |

미디어(스크린샷 · 데모 GIF)는 [`media/`](media/) 에 둔다.

---

## 코드를 고치면 어느 문서를 손봐야 하나

이 표가 곧 자동 검사의 기준이다. `scripts/docs-sync.sh` 가 같은 표를 들고 있고,
커밋할 때 **코드는 바뀌었는데 짝이 되는 문서는 그대로면 알려준다.**

| 고친 곳 | 같이 볼 문서 |
|---|---|
| `src/shared/Rules/**` | [rules.md](rules.md) · [open-questions.md](open-questions.md) |
| `src/shared/Cards/**` · `src/shared/Decks/**` | [decks.md](decks.md) · [rules.md](rules.md) |
| `src/shared/Matchmaking/**` · `src/server/Matchmaker/**` · `src/server/Arena.luau` · `src/server/Lobby.luau` | [matchmaking.md](matchmaking.md) |
| `src/client/UI/**` · `src/client/Controller.luau` · `src/client/App.luau` | [architecture.md](architecture.md) |
| `src/client/Tutorial.luau` | [tutorial.md](tutorial.md) |
| `src/server/DeckStore.luau` · `src/client/UI/DeckEditor.luau` | [decks.md](decks.md) |
| `src/shared/Net/**` | [architecture.md](architecture.md) |
| `tests/**` · `.github/workflows/**` | [testing.md](testing.md) |
| `scripts/**` | [testing.md](testing.md) · [getting-started.md](getting-started.md) |

검사는 **막지 않고 알려주기만 한다.** 문서가 필요 없는 수정(오타·리팩터)도 있는데
그때마다 커밋이 막히면 사람이 `--no-verify` 를 습관으로 쓰게 되고, 그러면 훅 전체가
무의미해진다.

경로가 진짜 있는지는 따로 본다 — `lune run tests/docs.luau` 가 문서 안의 파일 경로와
문서끼리의 링크를 전부 열어보고, 없는 것을 가리키면 **CI 를 빨간불로 만든다.**
이쪽은 정답이 분명해서 막아도 된다.
