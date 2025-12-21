# Windows 설치/기동 가이드 (NSSM 단일 표준)

이 문서는 **Windows 서비스화 표준 1안 = NSSM**으로 고정한 절차입니다.

## 1) 준비물

- Node.js 설치 확인
- NSSM 다운로드 (예: `C:\tools\nssm\nssm.exe`)
- 레포 경로 확인 (예: `E:\EMS\30. Development\Programming\ChatGPT\MES-Project`)

## 2) 서비스 설치 (자동 스크립트 사용)

레포 루트에서 실행:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```

## 3) 서비스 시작/중지/재시작/상태

```
nssm start MES-WebServer
nssm stop MES-WebServer
```

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\restart_windows_service.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\status_windows_service.ps1
```

## 4) 로그 확인

- `logs/windows_service/service_stdout.log`
- `logs/windows_service/service_stderr.log`

## 5) 점검 실행

서비스가 켜진 상태에서 Daily(P0)를 실행합니다.

health 확인(환경별 포트는 `MES_BASE_URL` 기준):
```
curl.exe -i "$env:MES_BASE_URL/health" -H "x-company-id: $env:MES_COMPANY_ID" -H "x-role: VIEWER"
```

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```
