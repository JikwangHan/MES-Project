# 운영 서버 원샷 동선 1페이지 (리허설 → 캡처 → 번들 → 제출)

이 문서는 **운영 서버에서 1회 리허설 실행 후 제출까지** 한 번에 끝내기 위한 표준 동선입니다.  
운영 산출물(ops_package/SOP/리허설/판정기)은 변경하지 않습니다.

---

## STEP 0) MODE 선택(필수, 3초)

- MODE=EXT(외부 제출) / MODE=INT(내부 제출)
- 애매하면 **무조건 EXT**로 진행(최소 노출)
- EXT 금지: 로컬 경로(COPIED_BUNDLE_PATH), 서버명/계정명, 내부 커밋 해시
- INT 허용: 필요 시 Commit(short) 포함 가능(권장: 파일명 중심)

---

## 0) 프리체크(60초)

1) 레포 상태 확인
```
git status -sb
```
2) .env 존재 확인(없으면 생성)
```
copy .env.example .env
```

---

## 1) 캡처 세션 생성(폴더 자동 준비)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\prepare_capture_session.ps1
```

생성 위치:
- 캡처 폴더: `ops_package/05_evidence/captures/<세션ID>/`
- 캡처 인덱스: `CAPTURE_INDEX_<세션ID>.md`

---

## 2) 운영자용 최종 5줄 실행

아래 문서의 **5줄을 그대로 복붙 실행**합니다.  
`ops_package/03_docs/REHEARSAL_Windows_5LINES_OPERATOR.md`

실행 중 해야 할 핵심 3가지(4번째 줄 직후):
1) `LATEST_BUNDLE=...` 확인  
2) 외부 제출이면 **파일명만** 사용  
3) `explorer.exe .`로 번들 폴더 열기

5번째 줄에서 `[PASS] HANDOVER READY`면 제출 확정입니다.

---

## 3) 필수 캡처 6장(증빙)

1) 서비스 등록 또는 상태 출력 화면  
2) `health 200` 결과  
3) Ticket-17.2 Daily(P0) PASS 근거 3줄  
4) hardening selfcheck PASS 라인 5줄  
5) evidence ZIP 생성 파일 목록  
6) HANDOVER_BUNDLE ZIP 생성 파일 목록(또는 LATEST_BUNDLE 출력 포함)

보안 규칙: `ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`

---

## 4) 제출 메시지(외부용 최소 노출)

### EXT 레일(외부 제출)

외부 제출 메시지 예시:
- `ops_package/03_docs/EXTERNAL_SUBMISSION_MESSAGE_EXAMPLES_2LINES.md`
- 포털 1줄 제한 시: **초압축 1줄** 사용

### INT 레일(내부 제출)

- 내부 운영 스레드 첫 줄 또는 `OPS_DIAG_LOG.md`에 기록
- 필요 시 Commit(short) 포함 가능(기본은 파일명 중심 유지)

---

## (선택) 개발 증빙(E2E)까지 함께

1) E2E 실행:
```
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_e2e_p0.ps1
```
2) E2E_META 자동 생성:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\e2e\print_e2e_meta.ps1 -Copy
```
3) Ticket-17.3의 “E2E 증빙(표준 5줄)” 섹션에 붙여넣기

---

## 최종 확인(모드 체크 1줄)

- 제출 직전: MODE=EXT이면 “파일명만 사용”인지 1초 확인
