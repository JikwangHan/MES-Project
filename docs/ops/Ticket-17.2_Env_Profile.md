# Ticket-17.2 환경 프로파일 안내 (초보자용)

이 문서는 **Ticket-17.2 판정기**를 여러 환경(개발/테스트/운영)에서 **동일한 방식**으로 실행하기 위한 안내서입니다.

## 1) 가장 먼저 할 일

1. 레포 루트의 `.env.example`을 복사해 `.env`를 만듭니다.
2. 본인 환경에 맞게 값만 바꿉니다.

예시:
```
copy .env.example .env
```

## 2) 기본 규칙 (우선순위)

실제 실행 시 값은 아래 순서로 결정됩니다.

1. **명령행 옵션** (가장 우선)
2. **환경변수** (PowerShell에서 직접 설정한 값)
3. **.env 파일**
4. **스크립트 기본값** (아무 설정이 없을 때만 사용)

즉, 운영에서는 **환경변수로 덮어쓰기**가 가능합니다.

## 3) .env에 넣는 값 (예시)

아래 항목은 `.env.example`에 들어 있는 값들입니다.

```
MES_BASE_URL=http://localhost:4000
MES_COMPANY_ID=COMPANY-A
T17_EQUIPMENT_CODE=T17-2-EQ-001
T17_GATEWAY_EQUIPMENT_CODE=EQ-GW-001
T17_RUN_GATEWAY_SMOKE=1
T17_GATEWAY_AUTO_KEY=1
T17_INCLUDE_P1=0
T17_AUTO_START_SERVER=0
T17_DEV_MODE=0
```

### 각 값의 의미

- `MES_BASE_URL`: MES 서버 주소
- `MES_COMPANY_ID`: 테스트할 회사 ID
- `T17_EQUIPMENT_CODE`: telemetry 테스트에 사용할 장비 코드
- `T17_GATEWAY_EQUIPMENT_CODE`: 게이트웨이 스모크에서 사용할 장비 코드
- `T17_RUN_GATEWAY_SMOKE`: 게이트웨이 스모크 실행 여부 (1=실행)
- `T17_GATEWAY_AUTO_KEY`: 장비키 자동 발급 옵션 (1=실행)
- `T17_INCLUDE_P1`: P1 확장 테스트 포함 여부 (1=실행)
- `T17_AUTO_START_SERVER`: 서버 자동 시작/종료 허용 (1=실행)
- `T17_DEV_MODE`: 개발 모드 허용 (1=실행)

## 4) 보안 주의사항

아래 값들은 **절대 커밋하지 않습니다.**

- `MES_MASTER_KEY`
- `MES_DEVICE_KEY`
- `MES_DEVICE_SECRET`

이 값들은 운영 환경의 보안 저장소나 비밀 관리 시스템에서 주입해야 합니다.

## 5) 실행 예시

P0만 실행:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1
```

P0 + P1 실행:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 -IncludeP1
```

게이트웨이까지 포함:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 -RunGatewaySmoke -GatewayAutoKey
```
