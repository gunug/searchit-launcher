# 출시 기록

출시할 때마다 맨 위에 새 항목을 추가하고 versionCode(빌드번호, `+N`)를 1씩 올린다.
**versionCode는 한 번 사용하면 재사용할 수 없다** — Google Play가 거부한다.
pubspec.yaml의 `version: <versionName>+<versionCode>` 와 항상 일치시킨다.

| versionName | versionCode | 날짜 | 상태 | 비고 |
|---|---|---|---|---|
| 1.0.0 | 4 | 2026-05-21 | 준비 중 | 검색 기능 개선: QWERTY 오타 보정, 영문 약어 검색, 단어 경계·부분 수열 매칭 |
| 1.0.0 | 3 | 2026-05-21 | 사용됨 | 앱 아이콘 신규 디자인 적용, versionCode 소진 |
| 1.0.0 | 2 | 2026-05-21 | 사용됨 | versionCode 소진 |
| 1.0.0 | 1 | — | 출시됨 | 최초 출시, versionCode 1 사용 완료 |

## 다음 출시 시
1. 위 표에서 가장 큰 versionCode + 1 을 새 versionCode로 사용
2. pubspec.yaml `version` 갱신 (예: `1.0.0+3`)
3. 이 표에 새 행 추가
