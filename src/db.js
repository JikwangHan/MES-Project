const path = require('path');
const Database = require('better-sqlite3');

const dbPath = path.join(__dirname, '..', 'data', 'mes.db');
const db = new Database(dbPath);

const ensureEquipmentColumns = () => {
  const columns = db.prepare(`PRAGMA table_info(equipments);`).all();
  const names = columns.map((c) => c.name);
  const addColumnIfMissing = (name, ddl) => {
    if (!names.includes(name)) {
      db.exec(`ALTER TABLE equipments ADD COLUMN ${ddl};`);
    }
  };
  addColumnIfMissing('device_key_id', 'device_key_id TEXT');
  addColumnIfMissing('device_key_secret_enc', 'device_key_secret_enc TEXT');
  addColumnIfMissing('device_key_status', "device_key_status TEXT DEFAULT 'ACTIVE'");
  addColumnIfMissing('device_key_issued_at', 'device_key_issued_at TEXT');
  addColumnIfMissing('device_key_last_seen_at', 'device_key_last_seen_at TEXT');
};

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
  ensureEquipmentColumns();

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

  // 텔레메트리 이벤트
  db.exec(`
    CREATE TABLE IF NOT EXISTS telemetry_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      equipment_id INTEGER NOT NULL,
      equipment_code TEXT NOT NULL,
      event_type TEXT NOT NULL,
      event_ts TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      received_at TEXT NOT NULL,
      FOREIGN KEY (equipment_id) REFERENCES equipments(id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_telemetry_company_ts
    ON telemetry_events (company_id, event_ts);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_telemetry_company_equipment
    ON telemetry_events (company_id, equipment_id);
  `);

  // 텔레메트리 nonce (리플레이 방지)
  db.exec(`
    CREATE TABLE IF NOT EXISTS telemetry_nonces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      equipment_id INTEGER NOT NULL,
      nonce TEXT NOT NULL,
      ts INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY (equipment_id) REFERENCES equipments(id),
      CONSTRAINT uniq_company_equipment_nonce UNIQUE (company_id, equipment_id, nonce)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_telemetry_nonce_company_equipment_ts
    ON telemetry_nonces (company_id, equipment_id, ts);
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

const getEquipmentByDeviceKey = (companyId, deviceKeyId) => {
  if (!companyId || !deviceKeyId) return null;

  const row = db
    .prepare(
      `SELECT
         id,
         company_id            AS companyId,
         name,
         code,
         process_id            AS processId,
         comm_type             AS commType,
         comm_config_json      AS commConfigJson,
         is_active             AS isActive,
         device_key_id         AS deviceKeyId,
         device_key_secret_enc AS deviceKeySecretEnc,
         device_key_status     AS deviceKeyStatus,
         device_key_issued_at  AS deviceKeyIssuedAt,
         device_key_last_seen_at AS deviceKeyLastSeenAt,
         created_at            AS createdAt
       FROM equipments
       WHERE company_id = @companyId
         AND device_key_id = @deviceKeyId
       LIMIT 1`
    )
    .get({ companyId, deviceKeyId });

  if (!row) return null;

  // telemetry.js는 snake_case 속성을 기대하므로 호환 형태로 반환
  return {
    id: row.id,
    company_id: row.companyId,
    name: row.name,
    code: row.code,
    process_id: row.processId,
    comm_type: row.commType,
    comm_config_json: row.commConfigJson,
    is_active: row.isActive,
    device_key_id: row.deviceKeyId,
    device_key_secret_enc: row.deviceKeySecretEnc,
    device_key_status: row.deviceKeyStatus,
    device_key_issued_at: row.deviceKeyIssuedAt,
    device_key_last_seen_at: row.deviceKeyLastSeenAt,
    created_at: row.createdAt,
  };
};

module.exports = { db, init, insertAuditLog, getEquipmentByDeviceKey };
