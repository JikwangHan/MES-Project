# NSSM 설치 가이드 (Windows 서비스화)

## 1) NSSM 설치

- NSSM을 다운로드한 뒤, `nssm.exe`가 있는 경로를 PATH에 추가합니다.

## 2) 서비스 등록

```
nssm install MES_Server "C:\Program Files\nodejs\node.exe" "src\server.js"
```

## 3) 필수 설정

- Startup directory: 레포 루트
- Environment:
  - `MES_MASTER_KEY` (운영 키)
  - `MES_BASE_URL` 등 필요한 변수

## 4) 시작/중지

```
nssm start MES_Server
nssm stop MES_Server
```
