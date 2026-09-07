#!/bin/sh
#
# 검사를 전부 돌린 뒤 플레이스를 만들어 Studio 로 연다.
#
#   sh scripts/studio.sh
#
# 왜 검사를 먼저 돌리나: Studio 는 스크립트가 죽어도 게임을 계속 돌린다.
# 출력창을 안 보고 있으면 "왜 버튼이 안 먹지" 를 화면만 보며 한참 헤매게 된다.
# 로컬 CI 가 그 오류를 먼저 잡아주므로, 통과한 뒤에 여는 편이 훨씬 빠르다.
#

cd "$(dirname "$0")/.." || exit 1

PATH="$HOME/.aftman/bin:$PATH"
export PATH

sh scripts/ci.sh --quiet || exit 1

printf "\033[2m› Studio 로 여는 중 (build.rbxlx)\033[0m\n"

case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) cmd //c start "" build.rbxlx ;;
	Darwin) open build.rbxlx ;;
	*)
		printf "이 플랫폼에서는 Studio 를 열 수 없습니다. build.rbxlx 를 직접 여세요.\n"
		exit 1
		;;
esac
