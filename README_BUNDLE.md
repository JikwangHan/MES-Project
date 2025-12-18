# mes_codex_bundle_repo_adaptive_v0_6

이 번들은 MES-System 레포 루트에서 실행하면, 레포의 실제 상태(package.json scripts, smoke.ps1, perf-gate.ps1, 폴더 구조)를 스캔해
`.codex/` 폴더에 “레포 100% 맞춤형” Codex 운영 파일을 자동 생성합니다.

## 포함 파일
- tools/codex-bundle-generate.ps1  (Windows PowerShell 실행용)
- tools/codex-bundle-generate.js   (Linux/Cloud 또는 Node 실행용)
- templates/*.template.md          (생성 템플릿)

## 사용 방법(초보자용)
### 1) 레포 루트에 폴더 그대로 복사
- 이 ZIP을 풀면 `tools/`와 `templates/`가 있습니다.
- MES-System 레포 루트에 그대로 복사합니다.

### 2) 생성 실행
Windows:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
powershell -ExecutionPolicy Bypass -File .\tools\codex-bundle-generate.ps1
```

Linux/Cloud:
```bash
node ./tools/codex-bundle-generate.js
```

### 3) 결과 확인
생성되면 레포 루트에 `.codex/`가 생기고, 아래 파일이 들어갑니다.
- .codex/AGENTS.md
- .codex/PLANS.md
- .codex/TICKET_PROMPTS.md
- .codex/QUALITY_GATE_CHECKLIST.md
- .codex/SESSION_START_PROMPT.md
- .codex/codex-scan-report.md

## 실패할 때(가장 흔한 3가지)
1) ZIP을 레포 루트가 아닌 다른 위치에 풀었다
2) PowerShell 실행 정책 때문에 ps1 실행이 막혔다
3) Node가 없어서 js 실행이 안 된다

이 경우에도 `.codex/codex-scan-report.md`가 없으면 “생성 자체가 실패”한 것입니다.
