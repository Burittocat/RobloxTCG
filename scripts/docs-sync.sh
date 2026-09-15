#!/bin/sh
#
# 코드는 바뀌었는데 짝이 되는 문서는 그대로인지 본다.
#
#   sh scripts/docs-sync.sh              지금 스테이지된 것 기준 (커밋 훅이 쓰는 방식)
#   sh scripts/docs-sync.sh --worktree   작업 트리 전체 기준
#
# **막지 않는다. 알려주기만 한다.** 오타 고침처럼 문서가 필요 없는 수정도 있는데
# 그때마다 커밋이 막히면 사람이 --no-verify 를 습관으로 쓰게 되고, 그러면 훅 전체가
# 무의미해진다. 경로가 실제로 있는지처럼 정답이 분명한 것만 CI 가 막는다
# (tests/docs.luau).
#
# 표는 docs/README.md 의 "코드를 고치면 어느 문서를 손봐야 하나" 와 같은 것이다.
# 문서를 늘리면 두 곳을 같이 고친다.
#

cd "$(dirname "$0")/.." || exit 1

YELLOW='\033[33m'
DIM='\033[2m'
RESET='\033[0m'

if [ "$1" = "--worktree" ]; then
	changed=$(git diff --name-only HEAD)
else
	changed=$(git diff --cached --name-only --diff-filter=ACMR)
fi

[ -z "$changed" ] && exit 0

# "코드 경로들|문서들" — 경로는 공백으로 나눈 glob 이다.
RULES='
src/shared/Rules/*|docs/rules.md docs/open-questions.md
src/shared/Cards/* src/shared/Decks/*|docs/rules.md docs/decks.md
src/shared/Matchmaking/* src/server/Matchmaker/* src/server/Arena.luau src/server/Lobby.luau|docs/matchmaking.md
src/client/UI/DeckEditor.luau src/server/DeckStore.luau|docs/decks.md
src/client/Tutorial.luau|docs/tutorial.md
src/client/UI/* src/client/Controller.luau src/client/App.luau src/shared/Net/*|docs/architecture.md
tests/* .github/workflows/*|docs/testing.md
scripts/*|docs/testing.md docs/getting-started.md
'

hits=""

echo "$RULES" | while IFS='|' read -r globs docs; do
	[ -z "$globs" ] && continue

	# 이 규칙에 걸리는 코드가 바뀌었나
	touched=""
	for file in $changed; do
		for glob in $globs; do
			# shellcheck disable=SC2254
			case "$file" in
				$glob) touched="$touched $file" ;;
			esac
		done
	done
	[ -z "$touched" ] && continue

	# 짝이 되는 문서 중 하나라도 같이 바뀌었으면 넘어간다
	documented=0
	for doc in $docs; do
		for file in $changed; do
			[ "$file" = "$doc" ] && documented=1
		done
	done
	[ "$documented" = 1 ] && continue

	printf "${YELLOW}! %s 를 고쳤는데 %s 는 그대로입니다.${RESET}\n" \
		"$(echo "$touched" | xargs -n1 | head -3 | tr '\n' ' ' | sed 's/ $//')" "$docs"
	printf "${DIM}  문서가 필요 없는 수정이면 그냥 커밋하세요. 이 검사는 막지 않습니다.${RESET}\n"
done

exit 0
