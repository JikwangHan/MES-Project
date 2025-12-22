<# 
  ops_package/02_scripts/push_diag_and_log.ps1

  Purpose
  - Print Annex E diagnostic results as a single line.
  - Optionally append the line to OPS_DIAG_LOG.md.

  Security
  - Do not record local paths, server names, account names, tokens, or commit hashes.
#>

param(
  [string]$Remote = "origin",
  [string]$Branch = "main",
  [switch]$AttemptPush,
  [switch]$AppendToOpsLog = $true,
  [string]$OpsDiagLogPath = "..\..\..\OPS_DIAG_LOG.md",
  [int]$TimeoutSec = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Get-KstNow {
  return (Get-Date).ToString("yyyy-MM-dd HH:mm")
}

function Test-Net443 {
  try {
    if (Get-Command Test-NetConnection -ErrorAction SilentlyContinue) {
      $r = Test-NetConnection github.com -Port 443 -WarningAction SilentlyContinue
      return [bool]$r.TcpTestSucceeded
    }
  } catch {
    # Fallback to TcpClient when Test-NetConnection is unavailable.
  }

  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect("github.com", 443, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(5))
    if ($ok) { $client.EndConnect($iar) }
    $client.Close()
    return $ok
  } catch {
    return $false
  }
}

function Run-LsRemote([string]$RemoteName) {
  $result = @{ Code = 1; Status = "FAIL" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = "ls-remote --heads $RemoteName"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $result.Code = $p.ExitCode

  if ($p.ExitCode -eq 0) {
    $result.Status = "PASS"
  } elseif ($stderr -match "403") {
    $result.Status = "403"
  } elseif ($stderr -match "401") {
    $result.Status = "401"
  } else {
    $result.Status = "FAIL"
  }

  return $result
}

function Run-Push([string]$RemoteName, [string]$BranchName, [int]$Timeout) {
  $result = @{ Code = 1; Status = "SKIPPED" }
  if (-not $AttemptPush) { return $result }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = "push --verbose $RemoteName $BranchName"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $null = $p.Start()

  $finished = $p.WaitForExit($Timeout * 1000)
  if (-not $finished) {
    try { $p.Kill() } catch {}
    $result.Status = "TIMEOUT"
    return $result
  }

  $stderr = $p.StandardError.ReadToEnd()
  $result.Code = $p.ExitCode

  if ($p.ExitCode -eq 0) {
    $result.Status = "OK"
  } elseif ($stderr -match "rejected" -or $stderr -match "denied") {
    $result.Status = "REJECTED"
  } else {
    $result.Status = "FAIL"
  }

  return $result
}

$net443 = if (Test-Net443) { "PASS" } else { "FAIL" }
$ls = Run-LsRemote -RemoteName $Remote
$push = Run-Push -RemoteName $Remote -BranchName $Branch -Timeout $TimeoutSec

$action = if ($push.Status -eq "OK") { "RETRY_LATER" } else { "AnnexD_SUBMIT_FIRST" }
$kst = Get-KstNow

$line = "PUSH_DIAG | KST=$kst | Net443=$net443 | LsRemote=$($ls.Status) | Push=$($push.Status) | Action=$action"

Write-Host $line

if ($AppendToOpsLog) {
  $logPath = Resolve-Path -Path $OpsDiagLogPath -ErrorAction SilentlyContinue
  if (-not $logPath) {
    Write-Host "[WARN] OPS_DIAG_LOG.md not found."
  } else {
    Add-Content -Path $logPath.Path -Value $line -Encoding utf8
    Write-Host "[PASS] OPS_DIAG_LOG.md 기록 완료"
  }
}
