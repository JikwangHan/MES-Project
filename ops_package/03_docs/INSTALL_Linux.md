# Linux 설치/기동 가이드 (systemd 기준)

이 문서는 **systemd 유닛 파일**로 MES 서버를 기동하는 표준 절차입니다.

## 1) 준비물

- Node.js 설치
- 레포 배포 경로 (예: `/opt/mes-project`)

## 2) 유닛 파일 배치

`ops_package/04_templates/systemd/mes.service` 파일을 복사합니다.

```
sudo cp ops_package/04_templates/systemd/mes.service /etc/systemd/system/mes.service
```

## 3) 환경 파일 준비

```
cp .env.example .env
```

운영 키는 `.env` 또는 systemd EnvironmentFile로 주입합니다.

## 4) 서비스 시작/중지

```
sudo systemctl daemon-reload
sudo systemctl enable mes
sudo systemctl start mes
sudo systemctl status mes
```

## 5) 로그 확인

```
sudo journalctl -u mes -n 200
```

## 6) 점검 실행

```
pwsh -NoProfile -ExecutionPolicy Bypass -File ./scripts/ops/run_ticket_17_2.ps1 -IncludeP1
```
