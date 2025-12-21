# 트러블슈팅 가이드 (현장 대응용)

| 증상 | 원인 | 확인 방법 | 해결 절차 | 재검증 |
|---|---|---|---|---|
| 서버 미기동 | 서버가 꺼져 있음 | `http://localhost:4000/health` 200 여부 | 서버를 먼저 실행하거나 `-AutoStartServer` 사용 | Daily 명령 재실행 |
| MES_BASE_URL 오류 | 주소/포트 오타 | `.env` 또는 환경변수 확인 | `MES_BASE_URL` 올바르게 수정 | Daily 명령 재실행 |
| 서명/nonce 실패 | 키 불일치, 중복 nonce | ticket17_2-errors 로그 확인 | 장비키 재발급 또는 nonce 재시도 | Pre-release 재실행 |
| equipmentCode 누락 | payload에 누락 | 체크리스트/로그 확인 | `T17_EQUIPMENT_CODE` 확인 후 재실행 | Daily 명령 재실행 |
| gateway profile 파싱 실패 | 프로파일 경로/JSON 오류 | gateway 로그 확인 | 프로파일 파일 재확인 | Gateway 포함 재실행 |
| gateway uplink 실패 | uplink 201 미수신 | gateway smoke 로그 확인 | MES 서버 상태 확인 후 재실행 | Daily 명령 재실행 |
