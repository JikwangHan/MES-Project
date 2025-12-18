#!/usr/bin/env node
/**
 * codex-bundle-generate.js
 *
 * 목적:
 * - 레포 루트에서 실행하면 package.json scripts, smoke.ps1, perf-gate.ps1, 폴더 구조를 스캔
 * - .codex/ 아래에 레포 맞춤형 AGENTS, PLANS, Ticket 프롬프트, 품질 게이트를 생성
 *
 * 주의:
 * - 추측 금지: 실제 파일을 읽어 확인합니다.
 * - 제품 기능 코드는 건드리지 않습니다(이번 작업은 .codex 생성이 목적).
 */
const fs = require("fs");
const path = require("path");

const ROOT = process.cwd();
const OUT_DIR = path.join(ROOT, ".codex");
const TEMPLATE_DIR = path.join(ROOT, "templates");
const LOCAL_TEMPLATE_DIR = path.join(__dirname, "..", "templates");

// 일부 폴더는 스캔에서 제외(속도/안전)
const IGNORE_DIRS = new Set([
  ".git", "node_modules", "dist", "build", "out", ".next", "coverage", ".turbo",
  ".idea", ".vscode", "bin", "obj", "target"
]);

function exists(p) {
  try { fs.accessSync(p); return true; } catch { return false; }
}

function readText(p) {
  return fs.readFileSync(p, "utf8");
}

function writeText(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content, "utf8");
}

function loadTemplate(name) {
  // 1) 레포 루트/templates 우선(프로젝트별 커스터마이징 허용)
  const p1 = path.join(TEMPLATE_DIR, name);
  if (exists(p1)) return readText(p1);

  // 2) 번들 내 templates 사용
  const p2 = path.join(LOCAL_TEMPLATE_DIR, name);
  if (exists(p2)) return readText(p2);

  throw new Error(`템플릿을 찾을 수 없습니다: ${name}`);
}

function safeJsonParse(text, label) {
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(`${label} JSON 파싱 실패: ${e.message}`);
  }
}

function scanPackageScripts() {
  const pkgPath = path.join(ROOT, "package.json");
  if (!exists(pkgPath)) return { pkgPath: null, scripts: {} };

  const pkg = safeJsonParse(readText(pkgPath), "package.json");
  const scripts = (pkg && pkg.scripts) ? pkg.scripts : {};
  return { pkgPath, scripts };
}

function scoreFile(p) {
  // 점수가 낮을수록 우선
  const norm = p.replace(/\\/g, "/").toLowerCase();
  let score = 1000;
  if (norm.includes("/scripts/")) score -= 300;
  if (norm.includes("/tools/")) score -= 200;
  if (norm.endsWith("/smoke.ps1")) score -= 50;
  if (norm.endsWith("/perf-gate.ps1")) score -= 50;
  // 루트에 가까울수록 우선
  const depth = norm.split("/").length;
  score += depth * 2;
  return score;
}

function findFilesByName(fileName, maxHits = 20) {
  const hits = [];
  const stack = [ROOT];

  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { continue; }

    for (const ent of entries) {
      const full = path.join(dir, ent.name);
      if (ent.isDirectory()) {
        if (IGNORE_DIRS.has(ent.name)) continue;
        // 너무 깊은 스캔 방지(대형 레포 대비)
        const rel = path.relative(ROOT, full);
        const depth = rel.split(path.sep).filter(Boolean).length;
        if (depth > 8) continue;
        stack.push(full);
      } else if (ent.isFile()) {
        if (ent.name.toLowerCase() === fileName.toLowerCase()) {
          hits.push(full);
          if (hits.length >= maxHits) return hits;
        }
      }
    }
  }
  return hits;
}

function chooseBest(hits) {
  if (!hits || hits.length === 0) return null;
  return hits
    .map(p => ({ p, score: scoreFile(p) }))
    .sort((a, b) => a.score - b.score)[0].p;
}

function makeCmds(scripts, smokePath, perfPath) {
  // 기본 후보
  const candidates = {
    lint: ["lint", "lint:fix", "eslint"],
    test: ["test", "test:unit", "test:ci"]
  };

  function scriptCmd(keys) {
    for (const k of keys) {
      if (scripts[k]) return `npm run ${k}`;
    }
    return "N/A";
  }

  const cmdLint = scriptCmd(candidates.lint);
  const cmdTest = scriptCmd(candidates.test);

  // ps1은 상대경로로 출력(복붙 편의)
  const cmdSmoke = smokePath ? `powershell -ExecutionPolicy Bypass -File .\\${path.relative(ROOT, smokePath).replace(/\//g, "\\")}` : "N/A";
  const cmdPerf = perfPath ? `powershell -ExecutionPolicy Bypass -File .\\${path.relative(ROOT, perfPath).replace(/\//g, "\\")}` : "N/A";

  return { cmdLint, cmdTest, cmdSmoke, cmdPerf };
}

function formatScriptsSummary(scripts) {
  const keys = Object.keys(scripts || {}).sort();
  if (!keys.length) return "- (package.json scripts 없음)";
  return keys.map(k => `- ${k}: ${scripts[k]}`).join("\n");
}

function render(template, vars) {
  let out = template;
  for (const [k, v] of Object.entries(vars)) {
    const token = `{{${k}}}`;
    out = out.split(token).join(v ?? "");
  }
  return out;
}

function main() {
  console.log("[codex-bundle] 레포 루트:", ROOT);

  const { pkgPath, scripts } = scanPackageScripts();
  console.log("[codex-bundle] package.json:", pkgPath ? "OK" : "없음");

  const smokeHits = findFilesByName("smoke.ps1");
  const perfHits = findFilesByName("perf-gate.ps1");

  const smokePath = chooseBest(smokeHits);
  const perfPath = chooseBest(perfHits);

  console.log("[codex-bundle] smoke.ps1:", smokePath ? path.relative(ROOT, smokePath) : "없음");
  console.log("[codex-bundle] perf-gate.ps1:", perfPath ? path.relative(ROOT, perfPath) : "없음");

  const { cmdLint, cmdTest, cmdSmoke, cmdPerf } = makeCmds(scripts, smokePath, perfPath);

  // .codex 생성
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const varsCommon = {
    SCRIPTS_SUMMARY: formatScriptsSummary(scripts),
    SMOKE_PATH: smokePath ? path.relative(ROOT, smokePath) : "N/A",
    PERF_GATE_PATH: perfPath ? path.relative(ROOT, perfPath) : "N/A",
    CMD_LINT: cmdLint,
    CMD_TEST: cmdTest,
    CMD_SMOKE: cmdSmoke,
    CMD_PERF: cmdPerf
  };

  // 파일 생성
  writeText(path.join(OUT_DIR, "AGENTS.md"), render(loadTemplate("AGENTS.template.md"), varsCommon));
  writeText(path.join(OUT_DIR, "PLANS.md"), render(loadTemplate("PLANS.template.md"), varsCommon));
  writeText(path.join(OUT_DIR, "TICKET_PROMPTS.md"), render(loadTemplate("TICKET_PROMPTS.template.md"), varsCommon));
  writeText(path.join(OUT_DIR, "QUALITY_GATE_CHECKLIST.md"), render(loadTemplate("QUALITY_GATE_CHECKLIST.template.md"), varsCommon));
  writeText(path.join(OUT_DIR, "SESSION_START_PROMPT.md"), render(loadTemplate("SESSION_START_PROMPT.template.md"), varsCommon));

  // 스캔 리포트
  const report = `# codex-scan-report.md

## 스캔 요약
- 레포 루트: ${ROOT}
- package.json: ${pkgPath ? "있음" : "없음"}
- smoke.ps1: ${varsCommon.SMOKE_PATH}
- perf-gate.ps1: ${varsCommon.PERF_GATE_PATH}

## 감지된 npm scripts
${varsCommon.SCRIPTS_SUMMARY}

## 품질 게이트(복붙용)
- lint: ${cmdLint}
- test: ${cmdTest}
- smoke: ${cmdSmoke}
- perf-gate: ${cmdPerf}

## 생성된 파일
- .codex/AGENTS.md
- .codex/PLANS.md
- .codex/TICKET_PROMPTS.md
- .codex/QUALITY_GATE_CHECKLIST.md
- .codex/SESSION_START_PROMPT.md
`;
  writeText(path.join(OUT_DIR, "codex-scan-report.md"), report);

  console.log("[codex-bundle] 완료: .codex/ 생성됨");
}

main();
