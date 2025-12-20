# Release Notes

## baseline-v0.3.15

### 테스트 매트릭스
- MES smoke (PowerShell 5.1): PASS
- MES smoke (pwsh): PASS
- Gateway smoke: PASS (uplink 201)
- Release-gate: PASS

### 증빙 로그 경로
- logs/smoke-ps51.log
- logs/smoke-pwsh.log
- logs/smoke-gateway-ps51.log
- logs/release-gate.log

### 변경 요약
- smoke 스크립트 UTF-8 처리 및 BOM 이슈 안정화
- gateway smoke 루트 실행 안정화 및 자동 키 발급 옵션
- edge-gateway 최소 런타임 스텁 복구
- sample_modbus_tcp.json 파싱 오류 수정

### 운영 영향
- 운영 영향 없음
- 자동 키 발급은 smoke 전용 옵션으로만 사용
