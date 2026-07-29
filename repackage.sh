#!/usr/bin/env bash
# ===========================================================================
# 공식 Bitwarden Firefox xpi 를 받아 "아이콘만" 교체 후 재포장.
#   - 코드는 한 줄도 안 건드림 → 업스트림 보안 패치가 그대로 흘러들어옴.
#   - 산출물: dist/src (web-ext 가 서명·패키징할 소스 디렉터리), dist/VERSION
#   - 서명/릴리스는 .github/workflows/repackage.yml 에서 web-ext sign 으로 처리.
#
# 로컬 테스트: bash repackage.sh icon.png  (imagemagick, jq, unzip, curl 필요)
# ===========================================================================
set -euo pipefail

SLUG="bitwarden-password-manager"        # AMO 슬러그
NEW_ID="bitwarden-icon@sushistack"       # 별도 애드온으로 서명되도록 id 변경 (Bitwarden id 는 소유 불가)
UPDATE_URL="https://github.com/sushistack/bitwarden-sidebar-icon/releases/download/latest/updates.json"  # 'latest' 고정 릴리스의 에셋 (Pages 불필요)
SRC_ICON="${1:-icon.png}"                # 교체할 단색 정사각 PNG (마스터 고해상도 권장)
AMO_API="https://addons.mozilla.org/api/v5/addons/addon/$SLUG/versions/?page_size=25"
SOAK_DAYS="${SOAK_DAYS:-14}"             # AMO 공개 후 이 일수가 지난 릴리스만 채택 (업스트림 회귀 숙성)
WORK="build"
DIST="dist"

command -v convert >/dev/null || { echo "✗ imagemagick(convert) 필요" >&2; exit 1; }
command -v jq      >/dev/null || { echo "✗ jq 필요" >&2; exit 1; }

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK/ext" "$DIST"

# PIN_VERSION 지정 시 해당 업스트림 버전으로 고정 — 롤백용이자 숙성 우회용
# (급한 보안 패치는 workflow_dispatch 로 pin_version 을 주면 즉시 당겨온다).
if [ -n "${PIN_VERSION:-}" ]; then
  echo "▶ 업스트림 $PIN_VERSION 고정 다운로드 (숙성 우회)"
  XPI_SRC=$(curl -fsSL "$AMO_API" | jq -r --arg v "$PIN_VERSION" '
    .results[] | select(.version == $v) | .file.url')
  [ -n "$XPI_SRC" ] || { echo "✗ AMO 최근 25개 버전에 $PIN_VERSION 없음" >&2; exit 1; }
else
  # 갓 나온 릴리스는 건너뛴다. 업스트림 회귀는 대개 며칠 안에 신고·패치되므로,
  # 숙성만으로 CI 가 잡을 수 없는 런타임 버그 대부분을 걸러낸다.
  echo "▶ ${SOAK_DAYS}일 이상 묵은 최신 업스트림 탐색 ($SLUG)"
  XPI_SRC=$(curl -fsSL "$AMO_API" | jq -r --argjson soak "$SOAK_DAYS" '
      .results
    | map(select((.file.created | fromdateiso8601) < (now - 86400 * $soak)))
    | sort_by(.file.created) | reverse
    | .[0].file.url // empty')
  [ -n "$XPI_SRC" ] || { echo "✗ ${SOAK_DAYS}일 넘게 묵은 업스트림 릴리스가 없음" >&2; exit 1; }
fi
curl -fsSL -o "$WORK/orig.xpi" "$XPI_SRC"

echo "▶ 압축 해제"
unzip -q "$WORK/orig.xpi" -d "$WORK/ext"

# AMO 예약 파일 제거 → 없으면 RESERVED_FILENAME 에러로 서명 거부됨.
#   - META-INF/ : 공식 xpi 의 기존 서명 파일
#   - mozilla-recommendation.json : Bitwarden 이 Mozilla 추천 확장이라 딸려옴
rm -rf "$WORK/ext/META-INF" "$WORK/ext/mozilla-recommendation.json"

MANIFEST="$WORK/ext/manifest.json"
UPSTREAM=$(jq -r '.version' "$MANIFEST")
REV="${BUILD_REV:-0}"                 # CI 에서 github.run_number 주입 → 재서명마다 유니크 버전
# AMO 는 id+version 중복 서명을 거부 → 4번째 자리로 회피.
# VERSION_OVERRIDE: 롤백 시 필요. Firefox 는 버전이 내려가면 자동 업데이트를 안 하므로,
# 옛 코드를 담되 버전 문자열은 현재 배포본보다 높게 찍어야 깨진 설치본이 스스로 복구된다.
BUILD_VERSION="${VERSION_OVERRIDE:-${UPSTREAM}.${REV}}"
echo "  upstream: $UPSTREAM  →  build: $BUILD_VERSION"

echo "▶ manifest 가 참조하는 모든 아이콘 경로 수집"
# default_icon 은 객체({size:path}) 또는 문자열(단일 path) 둘 다 가능 → 양쪽 처리.
mapfile -t ICON_PATHS < <(jq -r '
  [ (.icons // {} | .[])
  , (.browser_action.default_icon // empty | if type=="object" then .[] else . end)
  , (.action.default_icon         // empty | if type=="object" then .[] else . end)
  , (.sidebar_action.default_icon  // empty | if type=="object" then .[] else . end)
  , ((.action.theme_icons // .browser_action.theme_icons // [])[] | .light, .dark)
  ] | map(select(. != null)) | unique | .[]' "$MANIFEST")

echo "▶ 각 아이콘을 원본과 같은 크기로 우리 아이콘으로 교체"
for path in "${ICON_PATHS[@]}"; do
  [ -z "$path" ] && continue
  target="$WORK/ext/$path"
  if [ -f "$target" ]; then
    sz=$(identify -format '%wx%h' "$target[0]")   # 원본 파일의 실제 크기에 맞춤
  else
    sz="128x128"; mkdir -p "$(dirname "$target")"
  fi
  convert "$SRC_ICON" -resize "$sz" "$target"
  echo "  swapped $path ($sz)"
done

echo "▶ manifest id/name/version/update_url 패치 (별도 unlisted 애드온 + 자동 업데이트)"
tmp=$(mktemp)
jq --arg id "$NEW_ID" --arg upd "$UPDATE_URL" --arg ver "$BUILD_VERSION" '
    .browser_specific_settings.gecko.id = $id
  | .browser_specific_settings.gecko.update_url = $upd
  | .name = "Bitwarden (icon)"
  | .version = $ver
' "$MANIFEST" > "$tmp" && mv "$tmp" "$MANIFEST"

cp -R "$WORK/ext" "$DIST/src"
printf '%s' "$UPSTREAM"      > "$DIST/UPSTREAM"      # 업스트림 버전 (릴리스 중복 판정용)
printf '%s' "$BUILD_VERSION" > "$DIST/VERSION"       # 서명/태그용 빌드 버전
echo "✓ dist/src 준비 완료 (build $BUILD_VERSION)"
