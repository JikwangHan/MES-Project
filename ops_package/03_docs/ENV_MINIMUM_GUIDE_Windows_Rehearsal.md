# Windows 리허설용 .env 최소 입력값 가이드

이 문서는 **Windows NSSM 운영 리허설 1회**에 필요한 최소 환경값을 정리한 안내서입니다.

---

## 1) 목적

- 리허설 단계에서 **필수로 필요한 .env 값만 최소화**합니다.
- 값이 잘못되면 PASS가 나오지 않으므로, 아래 표를 기준으로 입력합니다.

---

## 2) 최소 필수 키(표)

| Key | 필수 여부 | 예시 값 | 설명 |
|---|---|---|---|
| MES_BASE_URL | 필수 | http://localhost:4000 | MES 서버 주소 |
| MES_COMPANY_ID | 필수 | COMPANY-A | 회사 ID |
| T17_EQUIPMENT_CODE | 필수 | EQ-MES-001 | telemetry 테스트 장비 코드 |
| T17_GATEWAY_EQUIPMENT_CODE | 선택 | EQ-GW-001 | 게이트웨이 스모크용 장비 코드 |
| T17_RUN_GATEWAY_SMOKE | 선택 | 0 또는 1 | 게이트웨이 스모크 실행 여부 |
| T17_GATEWAY_AUTO_KEY | 선택 | 0 또는 1 | 장비키 자동 발급 |
| T17_INCLUDE_P1 | 선택 | 0 또는 1 | P1 확장 테스트 포함 |
| T17_AUTO_START_SERVER | 권장 0 | 0 | NSSM이 기동하므로 0 권장 |
| T17_DEV_MODE | 권장 0 | 0 | 운영 리허설은 0 권장 |

---

## 3) 보안 규칙

- `.env`는 **커밋 금지**
- 키/토큰/비밀값 **콘솔 출력 금지**

---

## 4) 3줄 실행 예시

1) 템플릿 복사 → .env 생성
```
copy .\ops_package\04_templates\env\.env.rehearsal.windows.example .env
```

2) NSSM 서비스 기동
```
nssm start MES-WebServer
```

3) Ticket-17.2 P0 실행
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1
```
