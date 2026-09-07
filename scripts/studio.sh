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

#
# 지금 여는 것이 어느 코드인지 찍어둔다.
#
# Studio 에서 Ctrl+S 를 누르면 build.rbxlx 를 Studio 가 저장한 파일로 덮어쓴다.
# 그 창에서 그대로 게시하면 그때 열려 있던(= 낡았을 수 있는) 코드가 올라간다.
# 화면에 커밋 해시가 찍혀 있으면 "내가 지금 무엇을 게시하는지" 를 확인할 수 있다.
#
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "커밋 없음")
dirty=""
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
	dirty=" + 커밋 안 된 변경"
fi

printf "\033[2m› Studio 로 여는 중 — %s%s\033[0m\n" "$commit" "$dirty"
printf "\033[2m  (Studio 에서 저장하지 마세요. build.rbxlx 는 rojo 가 만드는 산출물입니다)\033[0m\n"

case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) cmd //c start "" build.rbxlx ;;
	Darwin) open build.rbxlx ;;
	*)
		printf "이 플랫폼에서는 Studio 를 열 수 없습니다. build.rbxlx 를 직접 여세요.\n"
		exit 1
		;;
esac
