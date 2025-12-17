const path = require('path');
const Database = require('better-sqlite3');

const dbPath = path.join(__dirname, '..', 'data', 'mes.db');
const db = new Database(dbPath);

const init = () => {
  // 기본 설정
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');

  // 기준정보: 품목유형
  db.exec(`
    CREATE TABLE IF NOT EXISTS item_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      parent_id INTEGER,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (parent_id) REFERENCES item_categories(id),
      CONSTRAINT uniq_company_code UNIQUE (company_id, code)
    );
  `);

  // 기준정보: 품목
  db.exec(`
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      category_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (category_id) REFERENCES item_categories(id),
      CONSTRAINT uniq_company_code_item UNIQUE (company_id, code)
    );
  `);

  // 기준정보: BOM (완제품-자재 관계)
  db.exec(`
    CREATE TABLE IF NOT EXISTS item_boms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      parent_item_id INTEGER NOT NULL,
      child_item_id INTEGER NOT NULL,
      qty REAL NOT NULL,
      unit TEXT,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (parent_item_id) REFERENCES items(id),
      FOREIGN KEY (child_item_id) REFERENCES items(id),
      CONSTRAINT uniq_company_bom UNIQUE (company_id, parent_item_id, child_item_id)
    );
  `);

  // 기준정보: 공정
  db.exec(`
    CREATE TABLE IF NOT EXISTS processes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      parent_id INTEGER,
      sort_order INTEGER DEFAULT 0,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (parent_id) REFERENCES processes(id),
      CONSTRAINT uniq_company_process UNIQUE (company_id, code)
    );
  `);

  // 기준정보: 설비
  db.exec(`
    CREATE TABLE IF NOT EXISTS equipments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      process_id INTEGER,
      comm_type TEXT,
      comm_config_json TEXT,
      is_active INTEGER DEFAULT 1,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (process_id) REFERENCES processes(id),
      CONSTRAINT uniq_company_equipment UNIQUE (company_id, code)
    );
  `);

  // 기준정보: 불량유형
  db.exec(`
    CREATE TABLE IF NOT EXISTS defect_types (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      process_id INTEGER,
      severity INTEGER DEFAULT 1,
      is_active INTEGER DEFAULT 1,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (process_id) REFERENCES processes(id),
      CONSTRAINT uniq_company_defect UNIQUE (company_id, code)
    );
  `);

  // 기준정보: 거래처
  db.exec(`
    CREATE TABLE IF NOT EXISTS partners (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      type TEXT NOT NULL,
      contact_name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      is_active INTEGER DEFAULT 1,
      created_by_role TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      CONSTRAINT uniq_company_partner UNIQUE (company_id, code)
    );
  `);

  // 감사 로그
  db.exec(`
    CREATE TABLE IF NOT EXISTS audit_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      actor_role TEXT NOT NULL,
      action TEXT NOT NULL,
      entity TEXT NOT NULL,
      entity_id INTEGER,
      payload TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);
};

const insertAuditLog = ({ companyId, actorRole, action, entity, entityId, payload }) => {
  const stmt = db.prepare(`
    INSERT INTO audit_logs (company_id, actor_role, action, entity, entity_id, payload)
    VALUES (@companyId, @actorRole, @action, @entity, @entityId, @payload)
  `);
  stmt.run({
    companyId,
    actorRole,
    action,
    entity,
    entityId,
    payload: payload ? JSON.stringify(payload) : null,
  });
};

module.exports = { db, init, insertAuditLog };
