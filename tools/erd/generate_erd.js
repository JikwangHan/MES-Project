/* tools/erd/generate_erd.js
 * 목적: SQLite 스키마를 읽어 Mermaid erDiagram(.mmd)을 자동 생성합니다.
 * - "현재 실제 테이블/컬럼명"과 100% 일치하도록 DB에서 직접 introspect 합니다.
 * - FK 관계(pragma_foreign_key_list) 기반으로 관계선도 생성합니다.
 *
 * 사용:
 *   node tools/erd/generate_erd.js --db data/mes.db --out docs/erd/mes_erd.mmd
 *
 * 주의:
 * - better-sqlite3는 프로젝트 의존성을 재사용합니다.
 */
'use strict';

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--db') args.db = argv[++i];
    else if (a === '--out') args.out = argv[++i];
    else if (a === '--snapshot') args.snapshot = argv[++i];
  }
  return args;
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function mapSqliteTypeToMermaid(t) {
  if (!t) return 'text';
  const s = String(t).toLowerCase();
  if (s.includes('int')) return 'int';
  if (s.includes('real') || s.includes('floa') || s.includes('doub')) return 'float';
  if (s.includes('bool')) return 'boolean';
  if (s.includes('date') || s.includes('time')) return 'datetime';
  return 'text';
}

function main() {
  const args = parseArgs(process.argv);
  const dbPath = args.db || 'data/mes.db';
  const outPath = args.out || 'docs/erd/mes_erd.mmd';
  const snapshotPath = args.snapshot || null;

  if (!fs.existsSync(dbPath)) {
    console.error(`[ERD] DB 파일이 없습니다: ${dbPath}`);
    console.error(`[ERD] 서버를 1회 실행하여 data/mes.db를 생성한 뒤 다시 시도하세요.`);
    process.exit(2);
  }

  // 로컬 의존성 재사용
  const Database = require('better-sqlite3');
  const db = new Database(dbPath, { readonly: true });

  // 테이블 목록(내부 sqlite_* 제외)
  const tables = db.prepare(`
    SELECT name
    FROM sqlite_master
    WHERE type='table'
      AND name NOT LIKE 'sqlite_%'
    ORDER BY name
  `).all().map(r => r.name);

  const schema = { tables: {}, foreignKeys: [] };

  for (const t of tables) {
    const cols = db.prepare(`PRAGMA table_info(${JSON.stringify(t)})`).all();
    const fks = db.prepare(`PRAGMA foreign_key_list(${JSON.stringify(t)})`).all();

    schema.tables[t] = {
      columns: cols.map(c => ({
        cid: c.cid,
        name: c.name,
        type: c.type,
        notnull: !!c.notnull,
        dflt_value: c.dflt_value,
        pk: !!c.pk
      })),
      foreignKeys: fks.map(f => ({
        id: f.id,
        seq: f.seq,
        table: t,
        refTable: f.table,
        from: f.from,
        to: f.to,
        on_update: f.on_update,
        on_delete: f.on_delete,
        match: f.match
      }))
    };

    for (const fk of schema.tables[t].foreignKeys) {
      schema.foreignKeys.push(fk);
    }
  }

  // Mermaid ERD 생성
  const lines = [];
  lines.push('%% Auto-generated: tools/erd/generate_erd.js');
  lines.push(`%% Source DB: ${dbPath}`);
  lines.push(`%% GeneratedAt: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('erDiagram');

  for (const t of tables) {
    lines.push(`  ${t} {`);
    for (const c of schema.tables[t].columns) {
      const mt = mapSqliteTypeToMermaid(c.type);
      // Mermaid erDiagram: "type fieldName [PK|FK]"
      const flags = [];
      if (c.pk) flags.push('PK');
      // FK 여부는 foreign_key_list로 판정
      const isFk = schema.tables[t].foreignKeys.some(fk => fk.from === c.name);
      if (isFk) flags.push('FK');
      const flagStr = flags.length ? ` ${flags.join(',')}` : '';
      lines.push(`    ${mt} ${c.name}${flagStr}`);
    }
    lines.push('  }');
  }

  // 관계선: 동일 테이블 FK가 여러 개면 중복이 생길 수 있으니 (table, refTable) + from/to로 유니크화
  const relSeen = new Set();
  for (const fk of schema.foreignKeys) {
    const key = `${fk.table}|${fk.refTable}|${fk.from}|${fk.to}`;
    if (relSeen.has(key)) continue;
    relSeen.add(key);

    // 기본 관계: child(table) many -> parent(refTable) one
    // Mermaid 문법 예: parent ||--o{ child : "fk_col"
    lines.push(`  ${fk.refTable} ||--o{ ${fk.table} : "${fk.from} -> ${fk.refTable}.${fk.to}"`);
  }

  const outDir = path.dirname(outPath);
  ensureDir(outDir);
  fs.writeFileSync(outPath, lines.join('\n') + '\n', 'utf8');

  if (snapshotPath) {
    ensureDir(path.dirname(snapshotPath));
    fs.writeFileSync(snapshotPath, JSON.stringify(schema, null, 2), 'utf8');
  }

  console.log(`[ERD] Mermaid ERD 생성 완료: ${outPath}`);
  if (snapshotPath) console.log(`[ERD] Schema snapshot 생성 완료: ${snapshotPath}`);
}

main();
