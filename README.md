# bitwarden-sidebar-icon

공식 Bitwarden Firefox 확장의 **아이콘만** 교체해 재포장하는 파이프라인.
코드는 한 줄도 안 건드리므로 업스트림 보안 패치가 그대로 따라온다 (userChrome 해킹처럼
Firefox 업데이트마다 깨지지 않음).

## 동작

`repackage.sh` → GH Actions(`repackage.yml`):

1. AMO에서 **14일 이상 묵은 최신 공식 Bitwarden xpi** 다운로드 (숙성 — 아래 참고)
   - `BLOCKED_VERSIONS`에 기록된 확인된 회귀 버전은 제외
2. manifest가 참조하는 모든 아이콘(`icons`, `action`, `sidebar_action`, `theme_icons`)을
   `icon.png` 로 리사이즈 교체
3. `browser_specific_settings.gecko.id` 를 `bitwarden-icon@sushistack` 로 변경 (별도 애드온)
4. 예약 실행은 새 후보 알림만 전송하고 종료
5. 수동 실행에서 `publish`를 체크한 경우에만 AMO 서명 후 `latest` 릴리스 교체

매주 월요일 후보를 확인하지만 자동 배포하지 않는다. 새 버전이 14일 숙성을 마친 뒤 처음 맞는
월요일에 ntfy 승인 알림을 보내며, 직접 확인한 뒤 `workflow_dispatch`의 `publish` 체크박스로
승인한다. 현재 배포된 업스트림과 같으면 알림 없이 건너뛴다.

## 숙성 & 롤백

업스트림 회귀(예: Bitwarden 2026.7.0과 Vaultwarden 1.36.0의 호환 문제로 보관함 무한 로딩)는
정적 CI가 잡을 수 없다. 빌드·서명은 정상이고 실제 볼트 데이터를 복호화할 때만 터지기 때문에
숙성 기간과 수동 승인을 함께 사용한다. 해당 호환 문제는 Vaultwarden 1.37.1 업그레이드로 해소했다.

- **숙성**: AMO 공개 후 `SOAK_DAYS`(기본 14일)가 지난 릴리스만 채택. 회귀는 대개 며칠 안에 신고·패치된다.
- **회귀 차단**: `BLOCKED_VERSIONS`(쉼표 구분)에 적힌 버전은 숙성 기간이 지나도 채택하지 않는다.
  현재 차단 버전은 없으며, 문제 발견 시 workflow env에 즉시 추가한다.
- **수동 승인**: 예약 실행은 절대 서명하거나 배포하지 않는다. 공식 확장을 실제 계정으로 확인한 뒤
  수동 실행 화면에서 `publish`를 체크해야만 `latest`가 교체된다.
- **긴급 우회**: `workflow_dispatch` 의 `pin_version` 에 버전을 주면 숙성을 건너뛰고 즉시 당겨온다.
- **롤백**: `pin_version` = 되돌릴 업스트림 버전. Firefox 는 자동 업데이트로 다운그레이드를
  하지 않으므로, 스크립트가 옛 코드에 최신 업스트림 기반의 높은 빌드 버전을 자동으로 찍는다.
  필요하면 `version_override`로 그 버전 문자열을 직접 지정할 수도 있다.

  ```
  gh workflow run repackage.yml -f publish=true -f pin_version=2026.6.1
  ```

  최신 버전보다 오래된 코드를 고르면 빌드 버전은 자동으로 `<최신 업스트림>.<run_number>`가 된다.
  따라서 Firefox가 다운그레이드로 무시하지 않고, `UPSTREAM.txt`에는 실제 코드 버전인 `2026.6.1`이
  기록되어 같은 롤백을 매주 다시 서명하지 않는다.

## 셋업

- 레포 Secrets:
  - `WEB_EXT_API_KEY`, `WEB_EXT_API_SECRET` — AMO API 키 (karakeep-sidebar 와 동일 계정)
  - `NTFY_URL` — 전체 토픽 URL (예: `https://notify.eli.kr/sidebars`). 미설정 시 알림만 스킵.
  - `NTFY_TOKEN` — self-hosted ntfy 인증 토큰 (선택; 익명 publish 가능하면 불필요)
- `icon.png` : 교체할 단색 정사각 PNG (고해상도 마스터; 현재 420×420)
- 레포는 **public** (release 에셋 URL이 인증 없이 공개되어야 자동 업데이트 가능). Pages 불필요.

## 자동 업데이트

- manifest `update_url` → `…/releases/download/latest/updates.json` (고정 `latest` 릴리스 에셋).
- 수동 승인된 빌드만 `latest`의 `updates.json` + `bitwarden-icon.xpi`를 교체한다.
- Firefox가 하루 안에 **조용히 자동 업데이트**(권한 변화 없으니 사용자 알림 없음).
- **단, update_url 이 박힌 빌드를 한 번은 수동 설치**해야 이후 자동 업데이트가 작동한다.

## 설치 (최초 1회)

Firefox에서 아래 URL을 열면 바로 설치 프롬프트 (MIME `application/x-xpinstall`):
`https://github.com/sushistack/bitwarden-sidebar-icon/releases/download/latest/bitwarden-icon.xpi`
기존 공식 Bitwarden과 **id가 다른 별도 애드온**이므로 공식 Bitwarden은 제거하고 이걸 쓴다.

## 버전 스킴

빌드 버전 = `<업스트림>.<github.run_number>` (예: `2026.5.1.42`). AMO는 id+version 중복 서명을
거부하므로 4번째 자리로 회피. 중복 판정은 *현재 배포된 updates.json의 업스트림*과 비교하므로
업스트림이 안 바뀌면 주간 cron이 재발행하지 않는다.

## 알아둘 점 (ponytail)

- **업데이트 출처가 본인 CI** → CI가 조용히 깨지면 금고 업데이트가 멈춘다. `NTFY_URL` 로 **실패 알림**을 받는 이유.
- **신뢰 홉 추가**: AMO API 키/CI가 금고 업데이트 경로에 낀다. 코드 무수정 재포장이라 위험은 작지만 키 관리는 신경 쓸 것.
