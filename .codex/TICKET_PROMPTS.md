# TICKET_PROMPTS.md (Plan / Execute / Review 프롬프트)

## 0) 세션 시작(가장 먼저 1회)
아래를 그대로 사용하세요.
- “레포의 .codex/SESSION_START_PROMPT.md를 읽고 그대로 적용해.”

---

## 1) Plan 프롬프트(티켓 시작)
```
[Ticket-XX] 목표: <한 문장>
범위: <수정 허용 폴더/파일>
제약: .codex/AGENTS.md 준수(추측 금지, companyId 강제, 민감정보 로그 금지, 단순성 우선)
산출물: 계획서만 작성. 코드 수정 금지.

- .codex/PLANS.md 템플릿으로 작성
- 실행 단계는 5~12 Step, Step 당 파일 1~2개
- 각 Step마다 검증 명령을 포함(반드시 실제 레포 명령)
- 모호한 점 질문 3~7개
```

## 2) Execute 프롬프트(항상 Step 1만)
```
[Ticket-XX] Plan의 Step 1만 수행해.
- 파일 1~2개만 수정
- 수정 후 Verify: lint/test + (있으면) smoke + (있으면) perf-gate
- 실패하면 원인 분석 후 최소 변경으로 1회 재시도
- 결과: diff 요약 + 검증 결과 요약만 보고
```

## 3) Review 프롬프트(커밋/PR 직전)
```
[Ticket-XX] 변경분을 리뷰해.
필수 체크:
- companyId 필터 누락 또는 우회 가능성 없음?
- role 인가 누락 없음?
- 민감정보 로그 노출 없음?
- 표준 에러코드/응답 포맷 일관성 유지?
- 페이징/limit 기본값/최대값 방어?
- N+1, 인덱스, 대용량 로딩 위험?
- smoke/perf-gate 기준 위반 가능성?
결과: 문제 목록(우선순위), 수정 제안, 영향 범위
```
