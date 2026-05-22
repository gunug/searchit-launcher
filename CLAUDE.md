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

### 1. 빌드 전 — versionCode 증가 (필수)

- **동일한 versionCode로는 절대 빌드하지 않는다.** 같은 코드를 Play Console에 올리면 거부 에러가 난다.
- 빌드 전에 [docs/releases.md](docs/releases.md) 표에서 가장 큰 versionCode를 확인하고, `pubspec.yaml`의 `version: <versionName>+<versionCode>` 에서 `+N` 을 +1 한다.
  - 예: `1.0.0+2` → `1.0.0+3`
- versionName(예: `1.0.0`)은 출시 내용에 따라 사용자가 정한다. versionCode는 무조건 단조 증가.
- 빌드 후 docs/releases.md 표에 새 행을 추가한다.

### 2. 빌드 후 — Play Console 업로드용 텍스트 제공 (필수)

빌드가 끝나면 사용자가 Play Console에 그대로 복붙할 수 있도록 다음 두 가지를 제시한다.

- **출시명 (Release name)**: 보통 `<versionName> (<versionCode>)` 형식. 예: `1.0.0 (3)`
- **출시 노트 (Release notes)**: Play Console 입력란 형식 그대로, 언어 태그를 포함해 제공한다.

  ```
  <ko-KR>
  이번 업데이트 내용을 여기에 작성.
  </ko-KR>
  <en-US>
  English release notes here.
  </en-US>
  ```

  - 이번 빌드의 실제 변경 사항을 반영해 한국어/영어 노트를 채워서 제공한다(빈 플레이스홀더로 두지 말 것).
  - 코드블록으로 감싸 복붙이 쉽도록 한다.
