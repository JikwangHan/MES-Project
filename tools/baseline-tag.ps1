<#
설명
- baseline-vMAJOR.MINOR.PATCH 태그를 자동으로 읽어 다음 태그를 계산합니다.
- 실수 방지를 위해 다음을 강제합니다.
  1) Git 작업트리가 clean 이어야 함(변경 파일이 있으면 중단)
  2) 기본은 develop 브랜치에서만 태그 생성 허용(원하면 -Branch로 변경 가능)
  3) 동일 태그가 이미 존재하면 중단
- 기본 동작은 "다음 태그를 출력"만 합니다.
- -Apply 를 주면 로컬 태그 생성
- -Push 를 주면 원격(origin) 태그 push까지 수행

사용 예시
- 다음 태그 계산만:
  pwsh .\tools\baseline-tag.ps1
- 0.3 시리즈로 강제해서 다음 태그 계산:
  pwsh .\tools\baseline-tag.ps1 -Series "0.3"
- 로컬 태그 생성(푸시는 안함):
  pwsh .\tools\baseline-tag.ps1 -Apply
- 로컬 태그 생성 + 원격 푸시:
  pwsh .\tools\baseline-tag.ps1 -Apply -Push
#>

[CmdletBinding()]
param(
  [string]$Series = "",
  [string]$Branch = "develop",
  [switch]$Apply,
  [switch]$Push,
  [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$msg) { Write-Host "[INFO] $msg" }
function Write-Warn([string]$msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

function Assert-GitRepo {
  git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "현재 폴더가 Git 레포가 아닙니다." }
}

function Assert-CleanWorkingTree {
  $status = git status --porcelain
  if ($status -and $status.Trim().Length -gt 0) {
    throw "작업트리가 clean이 아닙니다. 커밋/스태시 후 다시 시도하세요.`n$status"
  }
}

function Assert-OnBranch([string]$expectedBranch) {
  $current = (git rev-parse --abbrev-ref HEAD).Trim()
  if ($current -ne $expectedBranch) {
    throw "현재 브랜치가 '$current' 입니다. '$expectedBranch'에서만 태그 생성을 허용합니다."
  }
}

function Parse-BaselineTag([string]$tag) {
  if ($tag -match '^baseline-v(\d+)\.(\d+)\.(\d+)$') {
    return [pscustomobject]@{
      Tag   = $tag
      Major = [int]$Matches[1]
      Minor = [int]$Matches[2]
      Patch = [int]$Matches[3]
    }
  }
  return $null
}

function Get-LatestBaselineTag([string]$series) {
  git fetch --tags --prune --quiet | Out-Null

  $all = git tag --list "baseline-v*"
  $parsed = @()

  foreach ($t in $all) {
    $obj = Parse-BaselineTag $t
    if ($null -ne $obj) {
      if ([string]::IsNullOrWhiteSpace($series)) {
        $parsed += $obj
      } else {
        if ($series -match '^(\d+)\.(\d+)$') {
          $sMajor = [int]$Matches[1]
          $sMinor = [int]$Matches[2]
          if ($obj.Major -eq $sMajor -and $obj.Minor -eq $sMinor) {
            $parsed += $obj
          }
        } else {
          throw "Series 형식이 올바르지 않습니다. 예: -Series `"0.3`""
        }
      }
    }
  }

  if ($parsed.Count -eq 0) {
    return $null
  }

  $latest = $parsed | Sort-Object Major, Minor, Patch | Select-Object -Last 1
  return $latest
}

function Build-NextTag($latest) {
  if ($null -eq $latest) {
    return "baseline-v0.1.0"
  }
  $nextPatch = $latest.Patch + 1
  return ("baseline-v{0}.{1}.{2}" -f $latest.Major, $latest.Minor, $nextPatch)
}

function Assert-TagNotExists([string]$tag) {
  $exists = git tag --list $tag
  if ($exists -and $exists.Trim().Length -gt 0) {
    throw "태그 '$tag' 가 이미 존재합니다. 중복 생성은 금지합니다."
  }
}

Assert-GitRepo
Assert-CleanWorkingTree
Assert-OnBranch $Branch

$latest = Get-LatestBaselineTag $Series
if ($null -eq $latest) {
  Write-Warn "baseline 태그를 찾지 못했습니다. 초기 태그 baseline-v0.1.0 로 계산합니다."
} else {
  Write-Info ("최신 baseline 태그 감지: {0}" -f $latest.Tag)
}

$nextTag = Build-NextTag $latest
Assert-TagNotExists $nextTag

Write-Host $nextTag

if ($Apply) {
  Write-Info "로컬 태그 생성: $nextTag"
  git tag $nextTag
  if ($LASTEXITCODE -ne 0) { throw "git tag 실패" }

  if ($Push) {
    Write-Info "원격 태그 푸시: $Remote $nextTag"
    git push $Remote $nextTag
    if ($LASTEXITCODE -ne 0) { throw "git push tag 실패" }
  } else {
    Write-Warn "Push 옵션이 없어 원격 푸시는 수행하지 않았습니다."
  }
} else {
  Write-Info "Apply 옵션이 없어 계산/출력만 수행했습니다."
}
