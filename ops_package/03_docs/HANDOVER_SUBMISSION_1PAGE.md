# 운영 인수인계 제출 체크리스트 1페이지

아래 항목을 **체크박스 기준으로 모두 충족**하면 인수인계 제출이 완료됩니다.

---

## A) 제출물 필수 목록(체크박스)

- [ ] OPS_Package ZIP  
  - 경로: `ops_package/06_dist/OPS_Package_v0.1_*.zip`
- [ ] evidence ZIP  
  - 경로: `ops_package/05_evidence/evidence_*.zip`
- [ ] Ticket-17.2 체크리스트  
  - 경로: `docs/testing/Ticket-17.2_Test_Checklist.md`
- [ ] SOP v0.1  
  - 경로: `ops_package/03_docs/SOP_v0.1.md`
- [ ] HARDENING_1PAGE  
  - 경로: `ops_package/03_docs/HARDENING_1PAGE.md`
- [ ] RELEASE_NOTES.md (있는 경우)

---

## B) 절대 포함 금지(보안)

- [ ] `.env`
- [ ] 키/시크릿 파일(.key, .pem 등)
- [ ] 토큰/비밀번호가 들어간 문서

---

## C) 생성 절차(복붙 명령 3개)

1) Ticket-17.2 P0 실행
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1
```

2) evidence ZIP 생성
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\collect_evidence.ps1
```

3) OPS_Package ZIP 생성
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\build_ops_package.ps1 -Version "v0.1"
```

---

## D) 제출 전 최종 확인

- [ ] ZIP 파일 생성 시간 확인(최신인지)
- [ ] Ticket-17.2 자동 섹션이 최신 실행으로 갱신됐는지 확인
- [ ] evidence ZIP 안에 `.env`가 없는지 확인
- [ ] 번들 ZIP 포함 확인:
  - `check_handover_bundle_contents.ps1` 실행 후 PASS 확인
