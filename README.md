# SearchIt Launcher

> 한국어 초성·발음·오타까지 잡아내는 **검색 중심 Android 런처**

키패드 한 번이면 충분합니다. 아이콘을 화면 가득 늘어놓는 대신, 머릿속에 떠오른 대로 입력하면 원하는 앱이 맨 위에 뜹니다. `ㅋㅋ`로 카카오톡을, `instagram`으로 인스타그램을, 심지어 한/영 전환을 깜빡한 `rkrkdh`로도 앱을 찾습니다.

- **패키지**: `com.onethelab.searchitlauncher`
- **플랫폼**: Android (홈 런처 등록 가능)
- **기술 스택**: Flutter (Dart) + Kotlin Platform Channel (`PackageManager`)
- **저장소(public)**: https://github.com/gunug/searchit-launcher

---

## 왜 SearchIt 인가

| 일반 런처의 불편 | SearchIt의 해결 |
|---|---|
| 앱이 많아지면 폴더를 뒤적여야 함 | 떠오르는 대로 검색하면 끝 |
| 한글 앱은 정확히 입력해야 검색됨 | 초성(`ㅋㅋ`)·발음·로마자 모두 매칭 |
| 한/영 전환 깜빡하면 검색 실패 | QWERTY 자판 오타 자동 보정 |
| 영문 긴 앱 이름을 다 쳐야 함 | 약어(`gp` → Google Play)로 검색 |
| 자주 쓰는 앱이 묻힘 | 사용 빈도순 자동 정렬 + 잠금 고정 |

---

## 주요 기능

### 1. 강력한 한국어 검색 엔진

입력 한 줄을 **11단계 우선순위**로 채점해 가장 관련 높은 앱부터 보여줍니다. ([lib/search/search_engine.dart](lib/search/search_engine.dart))

| 검색 방식 | 입력 예시 | 결과 |
|---|---|---|
| **초성 검색** | `ㅋㅋ` | 카카오톡 |
| **발음 유사 검색** | `instagram` | 인스타그램 |
| **로마자 변환** | `kakao` | 카카오 |
| **QWERTY 오타 보정** | `rkrkdh` (가가오 자판) | 한/영 전환 없이 매칭 |
| **영문 약어** | `gp` | Google Play |
| **부분·단어경계 매칭** | `tube` | YouTube |
| **검색 이력 우선** | 이전에 `결제`로 연 앱 | 다음에 우선 노출 |

검색 채점 11단계 요약:

```
 1. 완전일치 (대소문자·공백 구분)
 2. 완전일치 (대소문자 무시)
 3. 완전일치 (정규화: 공백·대소문자 무시)
 4. startsWith
 5. 단어 경계 포함
 6. 부분 포함 (contains)
 7. 초성 일치
 8. 검색 이력 (최근일수록 가중)
 9. QWERTY 자판 오타
10. 발음 / 로마자 / 약어
11. LCS · 문자 중첩 · 부분 수열
```

한글 처리 로직(초성 추출, 개정 로마자 표기, 두벌식 QWERTY 역매핑, 자음 동등 폴딩 기반 발음 스켈레톤, 영문 약어 추출)은 모두 외부 의존성 없는 순수 규칙 기반으로 [lib/search/korean.dart](lib/search/korean.dart)에 구현돼 있습니다.

### 2. 사용 패턴에 맞춰 스스로 정리되는 화면

**2페이지 구조** ([lib/ui/home_screen.dart](lib/ui/home_screen.dart)):

- **왼쪽 페이지 — 앱 목록**: 전체 앱을 사용 빈도순으로 정렬해 세 섹션으로 분리
  - **신규 & 잠금**: 새로 설치한 앱(24시간)과 사용자가 고정한 앱
  - **사용**: 실행 이력이 있는 앱 (빈도순)
  - **미사용**: 한 번도 안 쓴 앱 (60% 흐리게 표시)
- **오른쪽 페이지 — 최근 & 검색**: 검색창 + 최근 실행한 앱

빈도 점수는 단순 횟수가 아니라 **시간 가중치** `Σ 1/(1+경과일)` 를 써서, 최근에 자주 쓴 앱일수록 위로 올라옵니다.

### 3. 뱃지 시스템

| 뱃지 | 의미 | 획득 / 상실 |
|---|---|---|
| **new** (초록) | 신규 설치 앱 | 설치 후 24시간 |
| **day** (노랑) | 꾸준히 쓰는 앱 | 7일 연속 실행 시 획득, 7일 미실행 시 상실 |
| **lock** (파랑) | 사용자가 고정한 앱 | 롱프레스 → 잠금 |

### 4. 앱 관리 (롱프레스 메뉴)

앱을 길게 누르면: **잠금/해제 · 기록 삭제 · 삭제(제거) · 앱 정보 · Play Store 이동**. 시스템 앱은 삭제가 비활성화되며, 삭제 실패 시 오류 메시지를 복사할 수 있는 다이얼로그를 띄웁니다. ([lib/ui/app_tile.dart](lib/ui/app_tile.dart))

### 5. 빠른 시작 — 3단계 점진적 로딩

런처는 켜질 때 즉시 반응해야 하므로 로딩을 3단계로 나눴습니다:

1. **캐시 메타데이터**로 즉시 UI 표시 (아이콘은 placeholder)
2. **네이티브 메타데이터** 갱신
3. 아이콘 없는 앱만 **병렬 로드**

또한 30일 이상 미사용 앱의 기록은 자동으로 정리됩니다.

### 6. 도네이션 (인앱 결제)

커피 / 음료 / 식사 / 큰 후원 4종 소비형 상품으로 제작자를 후원할 수 있습니다. ([lib/services/donation_service.dart](lib/services/donation_service.dart))

### 7. 완전한 한/영 병기 UI

모든 화면 텍스트가 한국어와 영어로 함께 표기되어 글로벌 사용자도 그대로 쓸 수 있습니다.

---

## 프로젝트 구조

```
searchit-launcher/
├── lib/
│   ├── main.dart                    # 앱 진입점
│   ├── models/
│   │   ├── app_entry.dart           # 앱 모델 + 검색용 파생 필드(초성·로마자·QWERTY·발음·약어)
│   │   └── badge.dart               # day 뱃지 획득/상실 로직
│   ├── search/
│   │   ├── korean.dart              # 한글 처리 (초성·로마자·QWERTY·발음 변환)
│   │   └── search_engine.dart       # 11단계 검색 채점 알고리즘
│   ├── services/
│   │   ├── app_service.dart         # 네이티브 플랫폼 채널 (앱 조회·실행·관리)
│   │   ├── storage_service.dart     # 이력·최근앱·뱃지·잠금 저장 (SharedPreferences)
│   │   └── donation_service.dart    # 인앱 결제 (후원)
│   └── ui/
│       ├── home_screen.dart         # 2페이지 홈 (앱 목록 / 검색)
│       └── app_tile.dart            # 그리드 타일 + 롱프레스 메뉴
├── android/
│   └── app/src/main/
│       ├── kotlin/.../MainActivity.kt   # Platform Channel (PackageManager)
│       └── AndroidManifest.xml          # 런처/홈 인텐트 필터, 권한
├── docs/
│   ├── releases.md                  # 버전별 출시 기록
│   └── production-checklist.md      # 프로덕션 출시 체크리스트
├── CLAUDE.md                        # 빌드/출시 워크플로 (서명·AAB·Play Console)
└── pubspec.yaml
```

---

## 빌드 & 실행

### 사전 준비

```bash
flutter pub get
```

### 개발용 실행

```bash
flutter run
```

### 런처 아이콘 생성

```bash
dart run flutter_launcher_icons
```

### 릴리즈 AAB 빌드

> **주의**: 빌드 전 반드시 `pubspec.yaml`의 versionCode(`+N`)를 +1 하세요. 같은 versionCode는 Play Console이 거부합니다. 상세 절차는 [CLAUDE.md](CLAUDE.md)의 **AAB 빌드 워크플로** 참조.

```bash
flutter build appbundle
# 결과물: build/app/outputs/bundle/release/app-release.aab
```

---

## 권한

| 권한 | 용도 |
|---|---|
| `REQUEST_DELETE_PACKAGES` | 롱프레스 메뉴의 앱 삭제 |
| `com.android.vending.BILLING` | 후원(인앱 결제) |
| `<queries>` (LAUNCHER) | Android 11+ 패키지 가시성 — 설치된 앱 목록 조회 |

런처/홈 등록을 위해 `MAIN`/`LAUNCHER` 및 `MAIN`/`HOME`/`DEFAULT` 인텐트 필터를 선언합니다.

---

## 의존성

| 패키지 | 버전 | 용도 |
|---|---|---|
| `shared_preferences` | ^2.3.2 | 검색 이력·최근 앱·뱃지·잠금 저장 |
| `in_app_purchase` | ^3.2.0 | 후원(Play Billing 6.x) |
| `cupertino_icons` | ^1.0.8 | 아이콘 |
| `flutter_launcher_icons` | ^0.14.4 | 런처 아이콘 생성 (dev) |

---

## 보안 주의사항

다음 파일은 **절대 git에 커밋하지 않습니다** (`.gitignore`로 추적 제외):

- `android/key.properties` — 서명 비밀번호 포함
- `android/upload-keystore.jks` — 업로드 키스토어

키스토어를 분실하면 동일 키로 앱 업데이트가 불가능하므로 별도의 안전한 곳에 백업하세요. 자세한 규칙은 [CLAUDE.md](CLAUDE.md) 참조.

---

## 출시 기록

[docs/releases.md](docs/releases.md) 참고. (현재: v1.2.4, versionCode 23 — 프로덕션 출시)

---

# 📣 홍보 전략

> 추후 홍보물(스토어 스크린샷, 영상, SNS 콘텐츠) 제작 시 활용할 마케팅 가이드.

## 1. 핵심 메시지 (Positioning)

**한 줄 슬로건 후보**

- "찾지 말고, 검색하세요" — *Don't scroll. Search.*
- "초성만 쳐도 열리는 런처"
- "한/영 전환은 이제 그만"

**가치 제안 (Value Proposition)**: SearchIt은 "앱을 정리하는" 런처가 아니라 "앱을 찾아주는" 런처입니다. 사용자는 폴더 구조를 고민할 필요 없이, 떠오르는 대로 입력만 하면 됩니다.

## 2. 타깃 사용자 (Persona)

| 세그먼트 | 페인 포인트 | SearchIt 소구점 |
|---|---|---|
| **앱 100개+ 헤비 유저** | 홈 화면 스크롤 지옥 | 검색 한 번에 도달 |
| **효율·생산성 추구형** | 불필요한 탭/스와이프 | 최소 입력, 빈도순 자동 정렬 |
| **한국어 사용자** | 한글 앱 검색 불편, 한/영 오타 | 초성·발음·QWERTY 보정 |
| **미니멀리스트** | 화려한 위젯·광고 피로 | 깔끔한 검색 중심 UI |

## 3. 차별화 포인트 (USP)

홍보물에서 반드시 강조할 "남들은 못 하는 것":

1. **초성 검색** — `ㅋㅋ` → 카카오톡 (한국 사용자 즉시 공감)
2. **한/영 오타 자동 보정** — `rkrkdh` 같은 자판 실수도 인식 (데모 영상 킬러 장면)
3. **발음 매칭** — 영문 입력으로 한글 앱, 한글 입력으로 영문 앱
4. **광고 없음 · 추적 없음** — 검색은 100% 온디바이스, 데이터 전송 없음
5. **가볍고 빠름** — 3단계 점진 로딩으로 즉각 반응

## 4. 데모 시나리오 (스크린샷 / 영상 스토리보드)

영상은 "마법 같은 순간"을 짧게 연속 배치하는 것이 효과적입니다:

1. `ㅋ` 한 글자 → 카카오톡이 맨 위로 (0.5초)
2. 한/영 전환 깜빡한 `rkrkdh` 입력 → 그래도 정확히 매칭 (놀라움 포인트)
3. `gp` → Google Play (약어의 편리함)
4. 자주 쓰는 앱이 빈도순으로 자동 정렬되는 화면
5. 잠금으로 즐겨찾는 앱 고정

> 권장 포맷: 15초 세로 영상(릴스/쇼츠), 자막은 한/영 병기.

## 5. 채널별 전략

| 채널 | 콘텐츠 |
|---|---|
| **Play Store** | 스크린샷 5장(검색/초성/오타보정/빈도정렬/잠금), 짧은 프로모 영상, 한·영 설명문 |
| **YouTube Shorts / Instagram Reels / TikTok** | "이 런처 검색 미쳤다" 류의 15초 데모 |
| **커뮤니티(클리앙·뽐뿌·레딧 r/androidapps)** | 개발기·기능 소개 글, 무광고/무추적 강조 |
| **개발 블로그 / GitHub** | 11단계 검색 알고리즘, 한글 QWERTY 역매핑 등 기술 스토리(개발자 유입) |

## 6. 스토어 최적화 (ASO) 키워드

`런처`, `초성 검색`, `앱 검색`, `한글 런처`, `미니멀 런처`, `생산성 런처`, `Korean launcher`, `search launcher`, `chosung`, `app drawer search`

## 7. 수익화 & 신뢰

- **무료 + 후원(도네이션)** 모델: 광고/구독 없이 자발적 후원으로 운영 → "광고 없는 깨끗한 런처" 메시지와 일관됨.
- 홍보 시 **"광고 없음 · 데이터 수집 없음 · 검색은 모두 기기 안에서"** 를 신뢰 배지처럼 전면에 노출.

## 8. 출시 단계별 로드맵 (제안)

1. **소프트 론칭**: 내부/비공개 테스트 → 핵심 버그·검색 정확도 피드백 수집
2. **커뮤니티 시딩**: 한국 안드로이드 커뮤니티에 개발기 공유, 초기 리뷰 확보
3. **콘텐츠 푸시**: 쇼츠/릴스 데모 영상 배포 (오타 보정 장면 중심)
4. **글로벌 확장**: 영문 설명·발음 검색 강조로 r/androidapps 등 해외 커뮤니티 공략

---

*Built with Flutter · Made by OneTheLab*
