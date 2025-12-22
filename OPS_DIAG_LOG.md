# OPS_DIAG_LOG (Internal Only)

## 작성 규칙(5줄)
1) 내부 전용: 외부 채널, 외부 제출 번들 ZIP에 포함 금지
2) 민감정보 금지: 로컬 경로, 서버명, 계정명, 토큰/키, 커밋 해시 외부 공유 금지
3) 시간 형식 고정: KST=YYYY-MM-DD HH:mm
4) 1라인 원칙: PUSH_DIAG/HANDOVER_RECORD는 SOP 템플릿 1줄 그대로 복붙
5) 사후 조치 기록: Action 값은 표준 값만 사용(예: AnnexD_SUBMIT_FIRST/RETRY_LATER)

## 복붙 템플릿
PUSH_DIAG | KST=YYYY-MM-DD HH:mm | Net443=PASS/FAIL | LsRemote=PASS/FAIL/403/401 | Push=OK/TIMEOUT/REJECTED | Action=AnnexD_SUBMIT_FIRST/RETRY_LATER
HANDOVER_RECORD | KST=YYYY-MM-DD HH:mm | Commit=________ | Bundle=________.zip | SessionId=________ | Judge=PASS | Push=DEFERRED(timeout) | Operator=________ | Target=Windows

## 로그(Entries)
# 예시: PUSH_DIAG | KST=2025-12-22 17:05 | Net443=PASS | LsRemote=PASS | Push=TIMEOUT | Action=AnnexD_SUBMIT_FIRST/RETRY_LATER
