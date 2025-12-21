# 운영 서버 하드닝 1페이지 요약 (v0.1)

## A) 방화벽 / 네트워크
- 운영 포트만 허용, 나머지는 차단
- 관리 접근은 사내망/VPN에서만
- health 노출 정책 결정(공개/비공개)

## B) 서비스 계정 / 권한 (NSSM)
- 가능하면 제한 계정 사용
- 앱 폴더: 읽기/실행
- logs 폴더: 쓰기
- ops_package/05_evidence: 쓰기(증빙 담당자만)
- .env: 읽기 제한(커밋 금지)

## C) 로그 / 증빙 / 환경파일 권한
- logs/windows_service 접근 제한
- 증빙 ZIP은 제출 담당자만 접근
- .env는 절대 ZIP에 포함 금지

## D) 포트 / 프로세스 정책
- URL은 항상 `MES_BASE_URL` 기준으로 통일
- 포트 충돌 진단:
  - Windows: `Get-NetTCPConnection -LocalPort <port>`
  - Linux: `ss -lntp | grep <port>`
- 서비스 복구 옵션(재시작 정책) 점검
