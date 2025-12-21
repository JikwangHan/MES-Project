# ENV 가이드 (초보자용)

이 폴더의 파일은 **환경별로 값을 쉽게 교체**하기 위한 템플릿입니다.

## 1) 기본 사용 방법

1. 레포 루트에서 `.env.example`을 복사하여 `.env`를 만듭니다.
2. `.env` 값을 내 환경에 맞게 수정합니다.

## 2) 환경별 템플릿

- `env.dev.example`: 개발 환경 예시
- `env.test.example`: 테스트 환경 예시
- `env.prod.example`: 운영 환경 예시 (값은 반드시 확인)

## 3) 반드시 확인해야 하는 값

- `MES_BASE_URL`: 서버 주소
- `MES_COMPANY_ID`: 회사 ID
- `T17_EQUIPMENT_CODE`: telemetry 테스트 장비 코드
- `T17_GATEWAY_EQUIPMENT_CODE`: 게이트웨이 스모크 장비 코드

## 4) 보안 주의사항

아래 값은 **절대 커밋하지 않습니다.**

- `MES_MASTER_KEY`
- `MES_DEVICE_KEY`
- `MES_DEVICE_SECRET`
