# Windows 설치/기동 가이드 (NSSM 기준)

이 문서는 **Windows 서비스 등록 1안(NSSM)**으로 고정한 절차입니다.

## 1) 준비물

- Node.js 설치
- NSSM 다운로드 및 PATH 등록
- 레포 경로: `E:\EMS\30. Development\Programming\ChatGPT\MES-Project`

## 2) 서비스 등록 (예시)

```
nssm install MES_Server "C:\Program Files\nodejs\node.exe" "src\server.js"
```

설치 후 **NSSM GUI**에서 아래를 설정합니다.

- Startup directory: 레포 루트
- Environment:
  - `MES_MASTER_KEY=운영키`
  - `MES_BASE_URL` 등 필요한 환경값

## 3) 서비스 시작/중지

```
nssm start MES_Server
nssm stop MES_Server
```

## 4) 로그 확인

- Windows 이벤트 로그 또는 NSSM 로그 파일 확인

## 5) 점검 실행

서비스가 켜진 상태에서 Daily(P0)를 실행합니다.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```
