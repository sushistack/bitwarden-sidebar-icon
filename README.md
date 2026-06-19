# bitwarden-sidebar-icon

공식 Bitwarden Firefox 확장의 **아이콘만** 교체해 재포장하는 파이프라인.
코드는 한 줄도 안 건드리므로 업스트림 보안 패치가 그대로 따라온다 (userChrome 해킹처럼
Firefox 업데이트마다 깨지지 않음).

## 동작

`repackage.sh` → GH Actions(`repackage.yml`):

1. AMO에서 **최신 공식 Bitwarden xpi** 다운로드
2. manifest가 참조하는 모든 아이콘(`icons`, `action`, `sidebar_action`, `theme_icons`)을
   `icon.png` 로 리사이즈 교체
3. `browser_specific_settings.gecko.id` 를 `bitwarden-icon@sushistack` 로 변경 (별도 애드온)
4. `web-ext sign --channel unlisted` 로 AMO 자동 서명
5. 서명된 `.xpi` 를 GitHub 릴리스로 발행

매주(월) + 수동(`workflow_dispatch`) 실행. 이미 릴리스된 업스트림 버전은 건너뜀.

## 셋업

- 레포 Secrets: `WEB_EXT_API_KEY`, `WEB_EXT_API_SECRET` (AMO API 키 — karakeep-sidebar 와 동일 계정)
- `icon.png` : 교체할 단색 정사각 PNG (고해상도 마스터; 현재 420×420)

## 설치

릴리스의 서명된 `.xpi` 를 Firefox에 끌어다 놓아 설치. 기존 공식 Bitwarden과 **id가 다른 별도 애드온**이므로,
공식 Bitwarden은 비활성화/제거하고 이걸 쓰면 된다.

## 알아둘 점 (ponytail)

- **업데이트 출처가 본인 CI**가 된다. CI가 조용히 깨지면 금고 업데이트가 멈추니, Actions 실패 알림을 켜둘 것.
- **신뢰 홉 추가**: AMO API 키/CI가 금고 업데이트 경로에 낀다. 코드 무수정 재포장이라 위험은 작지만, 키 관리는 신경 쓸 것.
- **자동 업데이트(update_url/updates.json) 미구현** — v1은 수동 설치. 필요해지면 추가.
- 같은 업스트림 버전을 **재서명**하려면(아이콘만 바꿔 다시) AMO가 중복 버전을 거부하므로 manifest version에 suffix를 붙여야 함.
