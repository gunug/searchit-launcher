# SearchIt Launcher

Flutter 기반 Android 런처 앱. 한국어 초성 검색을 지원한다.

- 패키지: `com.onethelab.searchitlauncher`
- 저장소(public): https://github.com/gunug/searchit-launcher

## 보안 — 키스토어 / 서명 (중요)

다음 파일은 **절대 git에 커밋하지 않는다.** 비밀번호와 서명 키가 들어있다.

- `android/key.properties` — 서명 설정(비밀번호 포함)
- `android/upload-keystore.jks` — 업로드 키스토어 본체

제외 설정은 두 곳에 모두 있다:
- 루트 `.gitignore` — `**/key.properties`, `**/*.jks`, `**/*.keystore`
- `android/.gitignore` — `key.properties`, `**/*.keystore`, `**/*.jks`

규칙:
- `git add -f` 등으로 키 파일을 강제 추가하지 말 것.
- 새 키 파일을 만들 때는 위 패턴에 매칭되는 위치/이름을 쓸 것.
- 키스토어는 git에 없으므로 분실하면 같은 키로 앱 업데이트가 불가능하다. 별도 안전한 곳에 백업해 둘 것.

## AAB 빌드 워크플로 (중요)

`flutter build appbundle` 으로 AAB를 빌드할 때는 **항상 아래 절차를 따른다.**

### 1. 빌드 전 — 버전 결정 (필수)

#### versionCode (빌드 번호, `+N`) — 무조건 +1
- **동일한 versionCode로는 절대 빌드하지 않는다.** 같은 코드를 Play Console에 올리면 거부 에러가 난다.
- [docs/releases.md](docs/releases.md) 표에서 가장 큰 versionCode를 확인하고 +1.
  - 예: 최대 12 → `pubspec.yaml`에 `+13`

#### versionName (`major.minor.patch`) — 변경 내용에 따라 결정
빌드 전에 사용자에게 versionName 변경 여부를 확인한다. 아무 말이 없으면 유지.

| 상황 | 예시 | 변경 |
|---|---|---|
| 버그 수정, 소규모 개선 | 삭제 버튼 수정, UI 텍스트 수정 | patch +1 (1.0.0 → 1.0.1) |
| 새 기능 추가, 동작 변경 | 섹션 분리, 뱃지 체계 변경 | minor +1 (1.0.0 → 1.1.0) |
| 전면 재설계, 비호환 변경 | 앱 구조 완전 개편 | major +1 (1.0.0 → 2.0.0) |

- patch는 자동 판단 가능. minor/major는 사용자 확인 후 결정.
- versionName 변경 시 docs/releases.md 표의 versionName 칼럼도 함께 갱신.
- 빌드 후 docs/releases.md 표에 새 행을 추가한다.

### 2. 빌드 후 — Play Console 내부 테스트 자동 출시 (필수)

빌드가 끝나면 **Python 스크립트로 직접 내부 테스트 트랙에 출시한다.** 사용자가 Play Console 웹을 열 필요 없다.

#### 인증 정보
- **서비스 계정 키**: `C:\Users\One The Lab\Downloads\effortless-launcher-e202f6c046c1.json`
  - git에 커밋하지 말 것. 분실 시 Play Console → 설정 → API 액세스에서 재발급.
- **패키지**: `com.onethelab.searchitlauncher`

#### 업로드 스크립트 (매번 아래 Python을 그대로 실행)

```python
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from google.oauth2 import service_account

KEY_FILE = r"C:\Users\One The Lab\Downloads\effortless-launcher-e202f6c046c1.json"
PACKAGE  = "com.onethelab.searchitlauncher"
AAB_PATH = r"<프로젝트루트>\build\app\outputs\bundle\release\app-release.aab"
TRACK    = "internal"
KO_NOTES = "<한국어 출시 노트>"
EN_NOTES = "<English release notes>"

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
creds   = service_account.Credentials.from_service_account_file(KEY_FILE, scopes=SCOPES)
service = build("androidpublisher", "v3", credentials=creds)

edit    = service.edits().insert(packageName=PACKAGE, body={}).execute()
edit_id = edit["id"]

media  = MediaFileUpload(AAB_PATH, mimetype="application/octet-stream", resumable=True, chunksize=5*1024*1024)
bundle = service.edits().bundles().upload(packageName=PACKAGE, editId=edit_id, media_body=media).execute(num_retries=5)

service.edits().tracks().update(
    packageName=PACKAGE, editId=edit_id, track=TRACK,
    body={"track": TRACK, "releases": [{"status": "completed",
        "versionCodes": [str(bundle["versionCode"])],
        "releaseNotes": [{"language": "ko-KR", "text": KO_NOTES},
                         {"language": "en-US", "text": EN_NOTES}]}]}
).execute()

service.edits().commit(packageName=PACKAGE, editId=edit_id).execute()
print(f"Done! versionCode {bundle['versionCode']} → internal track")
```

#### 절차 요약
1. versionName 변경 여부 판단 (patch 자동 / minor·major 사용자 확인)
2. `pubspec.yaml` versionCode +1, versionName 필요 시 변경
3. `docs/releases.md` 새 행 추가 (상태: 준비 중)
4. `rm -rf build && flutter build appbundle`
5. 위 Python 스크립트 실행 (KO_NOTES, EN_NOTES, AAB_PATH 채워서)
6. `docs/releases.md` 상태 → 출시됨
