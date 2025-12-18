/*
 * tools/patch-smoke-erd-gate.js
 * 목적: scripts/smoke.ps1에 ERD 게이트 유틸/호출을 안전하게 삽입(아이덴포턴트).
 * 사용:
 *   node tools/patch-smoke-erd-gate.js
 */
'use strict';

const fs = require('fs');
const path = require('path');

const SMOKE_PATH = path.join(__dirname, '..', 'scripts', 'smoke.ps1');

const FUNCTION_BLOCK = `
# ERD gate (optional)
function Invoke-ErdGate {
  param(
    [string]$DbPath = "data/mes.db",
    [string]$OutDir = "docs/erd"
  )

  if ($env:SMOKE_GEN_ERD -ne "1") {
    return
  }

  $strict = ($env:SMOKE_GEN_ERD_STRICT -eq "1")
  $render = ($env:SMOKE_GEN_ERD_RENDER -eq "1")
  $enforce = ($env:SMOKE_GEN_ERD_ENFORCE -eq "1")

  function Erd-Fail([string]$msg) {
    if ($strict) {
      throw $msg
    } else {
      Write-Host "[ERD][WARN] $msg" -ForegroundColor Yellow
    }
  }

  try {
    if (!(Test-Path $DbPath)) {
      Erd-Fail "DB 파일이 없습니다: $DbPath"
      return
    }

    $mmdPath = Join-Path $OutDir "mes_erd.mmd"
    Write-Host "[ERD] Mermaid 생성 시작" -ForegroundColor Cyan
    & node "tools/erd/generate_erd.js" --db $DbPath --out $mmdPath | Out-Null
    if (!(Test-Path $mmdPath)) {
      Erd-Fail "Mermaid 파일 생성 실패: $mmdPath"
      return
    }
    Write-Host "[ERD] Mermaid 생성 완료: $mmdPath" -ForegroundColor Green

    if ($render) {
      Write-Host "[ERD] PNG/PDF 렌더링 시작" -ForegroundColor Cyan
      try {
        & pwsh "tools/erd/render_erd.ps1" -Input $mmdPath -OutDir $OutDir | Out-Null
        Write-Host "[ERD] PNG/PDF 렌더링 완료" -ForegroundColor Green
      } catch {
        Erd-Fail "렌더링 실패: $($_.Exception.Message)"
      }
    }

    if ($enforce) {
      $dirty = & git status --porcelain -- "$OutDir/*.mmd"
      if ($dirty) {
        throw "ERD 산출물이 git에 반영되지 않았습니다. docs/erd/*.mmd 변경사항을 커밋하세요."
      }
    }
  } catch {
    Erd-Fail "ERD 게이트 실패: $($_.Exception.Message)"
  }
}
`.trimEnd();

const INVOKE_LINE = 'Invoke-ErdGate -DbPath "data/mes.db" -OutDir "docs/erd"';

function readUtf8WithBom(filePath) {
  const buf = fs.readFileSync(filePath);
  const hasBom = buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf;
  const text = hasBom ? buf.slice(3).toString('utf8') : buf.toString('utf8');
  return { text, hasBom };
}

function writeUtf8WithBom(filePath, text, hasBom) {
  if (hasBom) {
    const bom = Buffer.from([0xef, 0xbb, 0xbf]);
    fs.writeFileSync(filePath, Buffer.concat([bom, Buffer.from(text, 'utf8')]));
  } else {
    fs.writeFileSync(filePath, text, 'utf8');
  }
}

function insertBeforeMarker(text, markerRegex, insertBlock) {
  const match = text.match(markerRegex);
  if (!match || match.index == null) {
    return { text, inserted: false };
  }
  const idx = match.index;
  const before = text.slice(0, idx).trimEnd();
  const after = text.slice(idx);
  return { text: `${before}\n\n${insertBlock}\n\n${after}`, inserted: true };
}

function main() {
  if (!fs.existsSync(SMOKE_PATH)) {
    console.error(`[ERD] smoke.ps1 not found: ${SMOKE_PATH}`);
    process.exit(2);
  }

  const { text: original, hasBom } = readUtf8WithBom(SMOKE_PATH);
  let text = original;

  const hasFunction = /function\s+Invoke-ErdGate\b/.test(text);
  const hasInvoke = new RegExp(`^\\s*${INVOKE_LINE.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&')}\\s*$`, 'm').test(text);

  if (!hasFunction) {
    const markerRegex = /^#\s*-{5,}\s*\r?\n#\s*Ticket-04/i;
    const ins = insertBeforeMarker(text, markerRegex, FUNCTION_BLOCK);
    if (ins.inserted) {
      text = ins.text;
    } else {
      text = `${text.trimEnd()}\n\n${FUNCTION_BLOCK}\n`;
    }
  }

  if (!hasInvoke) {
    const markerRegex = /^Write-Host\s+"\[PASS\]\s*Ticket-13\.1/i;
    const ins = insertBeforeMarker(text, markerRegex, `${INVOKE_LINE}`);
    if (ins.inserted) {
      text = ins.text;
    } else {
      text = `${text.trimEnd()}\n\n# ---------------------------\n# Optional ERD Gate\n# ---------------------------\n${INVOKE_LINE}\n`;
    }
  }

  if (text !== original) {
    writeUtf8WithBom(SMOKE_PATH, text, hasBom);
    console.log('[ERD] smoke.ps1 updated.');
  } else {
    console.log('[ERD] smoke.ps1 already up-to-date.');
  }
}

main();
