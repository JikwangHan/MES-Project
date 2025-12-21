# 주간 로그 정리 스케줄(Windows Task Scheduler)

관리자 권한 PowerShell에서 실행하세요.

## 1) rotate_logs 주간 실행 등록

```
schtasks /Create /TN "MES_RotateLogs_Weekly" /SC WEEKLY /D SUN /ST 03:10 /RL HIGHEST ^
 /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%CD%\\ops_package\\02_scripts\\rotate_logs.ps1`" -RetentionDays 30 -ArchiveRetentionDays 180 -EvidenceRetentionDays 365 -ArchiveSubdir `"%CD%\\logs\\archive\\weekly`" -Compress"
```

## 2) (선택) 증빙 수집 주간 실행 등록

```
schtasks /Create /TN "MES_CollectEvidence_Weekly" /SC WEEKLY /D SUN /ST 03:20 /RL HIGHEST ^
 /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%CD%\\ops_package\\02_scripts\\collect_evidence.ps1`""
```
