# NSSM 설치 가이드 (Windows 서비스화)

## 1) NSSM 설치

- NSSM을 다운로드한 뒤, 예: `C:\tools\nssm\nssm.exe`에 둡니다.

## 2) 서비스 등록 (표준 스크립트)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```

## 3) 시작/중지

```
nssm start MES-WebServer
nssm stop MES-WebServer
```
