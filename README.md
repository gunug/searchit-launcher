# SearchIt Launcher

한국어 초성 검색을 지원하는 Flutter 기반 Android 런처 앱.

- **패키지**: `com.onethelab.searchitlauncher`
- **플랫폼**: Android
- **기술 스택**: Flutter (Dart) + Kotlin (Platform Channel)

---

## 주요 기능

### 검색
- **초성 검색**: "ㅋㅋ" 입력 시 "카카오톡" 검색
- **발음 유사 검색**: "instagram" 입력 시 "인스타그램" 검색
- **QWERTY 오타 보정**: 한/영 전환 없이 잘못 입력한 텍스트 자동 보정 (예: `rkrkdh` → "가가오")
- **영문 약어**: "gp" → "Google Play"
- **검색 이력**: 유사/관련 섹션에서 실행한 검색어를 기억해 다음 번에 우선 표시

### 검색 결과 4단계 분류
| 섹션 | 설명 |
|------|------|
| **match** | 앱 이름/패키지에 검색어가 포함되거나 초성이 일치 |
| **history** | 과거에 비슷한 상황에서 실행했던 앱 |
| **similar** | 발음(로마자·QWERTY·음운)이 유사한 앱 |
| **related** | LCS·부분 수열 등 문자 유사도로 연관된 앱 |

각 앱은 4개 섹션 중 **하나에만** 표시되며, 섹션 내에서는 관련도 → 이름 순으로 정렬됩니다.

### 런처 기능
- **최근 앱**: 검색창이 비어있을 때 최근 실행한 앱 30개 표시
- **new 뱃지**: 설치 후 7일 이내 신규 앱에 표시
- **롱프레스 메뉴**: 앱 삭제 / 앱 정보 / Play Store 이동
- **홈 런처 등록**: Android 홈 스크린 런처로 설정 가능

---

## 프로젝트 구조

```
searchit-launcher/
├── lib/
│   ├── main.dart                 # 앱 진입점
│   ├── models/
│   │   └── app_entry.dart        # 앱 정보 모델 (이름, 패키지, 아이콘, 설치시간)
│   ├── search/
│   │   ├── korean.dart           # 한글 처리 (초성·로마자·QWERTY·음운 변환)
│   │   └── search_engine.dart    # 4단계 검색 분류 알고리즘
│   ├── services/
│   │   ├── app_service.dart      # 네이티브 플랫폼 채널 (앱 조회·실행·관리)
│   │   └── storage_service.dart  # 검색 이력 및 최근 앱 저장 (SharedPreferences)
│   └── ui/
│       ├── home_screen.dart      # 홈 화면 (검색창 + 결과 목록)
│       └── app_tile.dart         # 앱 그리드 타일 + 롱프레스 메뉴
├── android/
│   └── app/src/main/
│       ├── kotlin/.../MainActivity.kt  # Platform Channel 구현 (PackageManager)
│       └── AndroidManifest.xml         # 런처 인텐트 필터, 권한
├── docs/
│   ├── functions.md              # 검색 규칙 및 기능 명세
│   └── releases.md               # 버전별 출시 기록
└── pubspec.yaml
```

---

## 빌드

### 사전 준비

```bash
flutter pub get
```

### 개발용 실행

```bash
flutter run
```

### 릴리즈 AAB 빌드

> **주의**: 빌드 전에 반드시 `pubspec.yaml`의 versionCode를 증가시켜야 합니다.  
> 자세한 절차는 [CLAUDE.md](CLAUDE.md)의 **AAB 빌드 워크플로** 섹션을 참고하세요.

```bash
flutter build appbundle
```

빌드 결과물: `build/app/outputs/bundle/release/app-release.aab`

---

## 보안 주의사항

다음 파일은 **절대 git에 커밋하지 않습니다.**

- `android/key.properties` — 서명 비밀번호 포함
- `android/upload-keystore.jks` — 업로드 키스토어

두 파일 모두 `.gitignore`에 의해 추적이 제외되어 있습니다.  
키스토어를 분실하면 동일 키로 앱 업데이트가 불가능하므로 별도의 안전한 곳에 백업해 두세요.

---

## 의존성

| 패키지 | 버전 | 용도 |
|--------|------|------|
| `shared_preferences` | ^2.3.2 | 검색 이력, 최근 앱 저장 |
| `cupertino_icons` | ^1.0.8 | 아이콘 |
| `flutter_launcher_icons` | ^0.14.4 | 런처 아이콘 생성 (dev) |

---

## 출시 기록

[docs/releases.md](docs/releases.md) 참고.
