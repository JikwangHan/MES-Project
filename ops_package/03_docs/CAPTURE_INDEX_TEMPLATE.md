# 캡처 인덱스 템플릿 (운영 리허설용)

## 1) 파일명 규칙

```
YYYYMMDD_HHMM_번호_설명.png
```

예시:
```
20251221_1030_01_Service_Installed.png
```

## 2) 캡처 목록(#1~#6)

1. 서비스 등록 완료 화면 또는 status 출력
2. health 200 결과 화면
3. Ticket-17.2 PASS 근거 라인 3줄
4. hardening_selfcheck PASS 라인 5줄
5. evidence ZIP 생성 파일 목록
6. HANDOVER_BUNDLE 생성 파일 목록

## 3) 저장 위치

- 권장: `ops_package/05_evidence/captures/`

## 4) 보안 주의

- 캡처에 **비밀값(.env, 키, 토큰)**이 보이면 안 됩니다.
