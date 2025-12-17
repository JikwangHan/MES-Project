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
