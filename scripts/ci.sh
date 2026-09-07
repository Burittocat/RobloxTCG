#!/bin/sh
#
# 로컬 CI. 사람과 git 훅이 **같은 것**을 돌린다.
#
#   sh scripts/ci.sh            결과를 전부 보면서
#   sh scripts/ci.sh --quiet    실패했을 때만 출력 (훅이 쓰는 방식)
#
# 단계와 순서는 .github/workflows/ci.yml 과 같다.
# 여기서 통과하면 GitHub 에 올려도 통과한다 (툴 버전도 aftman.toml 로 같다).
#

cd "$(dirname "$0")/.." || exit 1

# aftman 이 깐 도구는 ~/.aftman/bin 에 있다.
# 에디터가 띄운 셸은 로그인 셸과 PATH 가 다를 수 있어 직접 얹어둔다.
PATH="$HOME/.aftman/bin:$PATH"
export PATH

GREEN='\033[32m'
RED='\033[31m'
DIM='\033[2m'
RESET='\033[0m'

QUIET=0
if [ "$1" = "--quiet" ]; then
	QUIET=1
fi

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		printf "${RED}%s 를 찾을 수 없습니다.${RESET} 저장소에서 'aftman install' 을 먼저 실행하세요.\n" "$1"
		exit 1
	fi
}

need lune
need rojo

# 실패했을 때만 출력을 보여준다. 통과한 검사의 로그 100줄은 아무도 안 읽는다.
run() {
	label=$1
	shift

	printf "${DIM}› %s${RESET}\n" "$label"

	if [ "$QUIET" = 1 ]; then
		if ! output=$("$@" 2>&1); then
			printf "%s\n" "$output"
			printf "\n${RED}✗ %s 실패${RESET}\n" "$label"
			exit 1
		fi
	else
		if ! "$@"; then
			printf "\n${RED}✗ %s 실패${RESET}\n" "$label"
			exit 1
		fi
	fi
}

run "문법 검사 (전체 .luau)" lune run tests/check.luau
run "룰 엔진 테스트" lune run tests/run.luau
run "스모크 테스트 (서버+클라 실행)" lune run tests/smoke.luau
run "플레이스 빌드" rojo build --output build.rbxlx

printf "${GREEN}로컬 CI 통과${RESET}\n"
