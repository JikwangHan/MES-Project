# Cloud 설치/기동 가이드 (Linux VM 기준)

이 문서는 **리눅스 VM + systemd** 방식으로 고정한 최소 운영 절차입니다.

## 1) 권장 구성

- VM OS: Ubuntu LTS
- Node.js 설치
- 보안 그룹: 4000 포트 허용

## 2) 배포 경로

예시: `/opt/mes-project`

```
sudo mkdir -p /opt/mes-project
```

## 3) 환경 파일 준비

```
cp .env.example .env
```

운영 키는 VM의 보안 저장소 또는 EnvironmentFile로 주입합니다.

## 4) systemd 등록

```
sudo cp ops_package/04_templates/systemd/mes.service /etc/systemd/system/mes.service
sudo systemctl daemon-reload
sudo systemctl enable mes
sudo systemctl start mes
```

## 5) 점검 실행

```
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/ops/run_ticket_17_2.ps1 -IncludeP1
```
