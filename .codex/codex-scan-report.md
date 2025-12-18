# codex-scan-report.md

## 스캔 요약
- 레포 루트: E:\EMS\30. Development\Programming\ChatGPT\MES-Project
- package.json: 있음
- smoke.ps1: scripts\smoke.ps1
- perf-gate.ps1: N/A

## 감지된 npm scripts
- start: node src/server.js

## 품질 게이트(복붙용)
- lint: N/A
- test: N/A
- smoke: powershell -ExecutionPolicy Bypass -File .\scripts\smoke.ps1
- perf-gate: N/A

## 생성된 파일
- .codex/AGENTS.md
- .codex/PLANS.md
- .codex/TICKET_PROMPTS.md
- .codex/QUALITY_GATE_CHECKLIST.md
- .codex/SESSION_START_PROMPT.md
