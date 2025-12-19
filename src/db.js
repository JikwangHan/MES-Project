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

const ensureQualityInspectionColumns = () => {
  const columns = db.prepare(`PRAGMA table_info(quality_inspections);`).all();
  const names = columns.map((c) => c.name);
  const addColumnIfMissing = (name, ddl) => {
    if (!names.includes(name)) {
      db.exec(`ALTER TABLE quality_inspections ADD COLUMN ${ddl};`);
    }
  };
  addColumnIfMissing('lot_id', 'lot_id INTEGER');
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

  // 생산 실행: 작업지시
  db.exec(`
    CREATE TABLE IF NOT EXISTS work_orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      wo_no TEXT NOT NULL,
      item_id INTEGER NOT NULL,
      process_id INTEGER NOT NULL,
      equipment_id INTEGER,
      plan_qty REAL NOT NULL,
      status TEXT NOT NULL,
      scheduled_start_at TEXT,
      scheduled_end_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (item_id) REFERENCES items(id),
      FOREIGN KEY (process_id) REFERENCES processes(id),
      FOREIGN KEY (equipment_id) REFERENCES equipments(id),
      CONSTRAINT uniq_company_wo UNIQUE (company_id, wo_no)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_work_orders_company_status
    ON work_orders (company_id, status);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_work_orders_company_created
    ON work_orders (company_id, created_at);
  `);

  // 생산 실행: 실적
  db.exec(`
    CREATE TABLE IF NOT EXISTS production_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      work_order_id INTEGER NOT NULL,
      good_qty REAL NOT NULL,
      defect_qty REAL NOT NULL,
      event_ts TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (work_order_id) REFERENCES work_orders(id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_results_company_wo
    ON production_results (company_id, work_order_id);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_results_company_event
    ON production_results (company_id, event_ts);
  `);

  // 품질: 검사 헤더
  db.exec(`
    CREATE TABLE IF NOT EXISTS quality_inspections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      inspection_no TEXT NOT NULL,
      work_order_id INTEGER,
      item_id INTEGER,
      process_id INTEGER,
      equipment_id INTEGER,
      inspection_type TEXT NOT NULL,
      status TEXT NOT NULL,
      inspected_at TEXT DEFAULT (datetime('now')),
      inspector_name TEXT,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (work_order_id) REFERENCES work_orders(id),
      FOREIGN KEY (item_id) REFERENCES items(id),
      FOREIGN KEY (process_id) REFERENCES processes(id),
      FOREIGN KEY (equipment_id) REFERENCES equipments(id),
      CONSTRAINT uniq_company_inspection_no UNIQUE (company_id, inspection_no)
    );
  `);
  ensureQualityInspectionColumns();

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_quality_inspections_company_inspected
    ON quality_inspections (company_id, inspected_at);
  `);

  // 품질: 검사 불량 상세
  db.exec(`
    CREATE TABLE IF NOT EXISTS quality_inspection_defects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      inspection_id INTEGER NOT NULL,
      defect_type_id INTEGER NOT NULL,
      qty REAL NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (inspection_id) REFERENCES quality_inspections(id),
      FOREIGN KEY (defect_type_id) REFERENCES defect_types(id),
      CONSTRAINT uniq_company_inspection_defect UNIQUE (company_id, inspection_id, defect_type_id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_quality_defects_company_inspection
    ON quality_inspection_defects (company_id, inspection_id);
  `);

  // 품질: 검사 항목 마스터
  db.exec(`
    CREATE TABLE IF NOT EXISTS quality_check_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      name TEXT NOT NULL,
      code TEXT NOT NULL,
      data_type TEXT NOT NULL,
      unit TEXT,
      lower_limit REAL,
      upper_limit REAL,
      target_value REAL,
      is_required INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now')),
      CONSTRAINT uniq_company_check_item UNIQUE (company_id, code)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_quality_check_items_company_code
    ON quality_check_items (company_id, code);
  `);

  // 품질: 검사 결과(측정값)
  db.exec(`
    CREATE TABLE IF NOT EXISTS quality_inspection_results (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      inspection_id INTEGER NOT NULL,
      check_item_id INTEGER NOT NULL,
      measured_value_num REAL,
      measured_value_text TEXT,
      measured_value_bool INTEGER,
      judgement TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (inspection_id) REFERENCES quality_inspections(id),
      FOREIGN KEY (check_item_id) REFERENCES quality_check_items(id),
      CONSTRAINT uniq_company_inspection_check UNIQUE (company_id, inspection_id, check_item_id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_quality_results_company_inspection
    ON quality_inspection_results (company_id, inspection_id);
  `);

  // LOT: 마스터
  db.exec(`
    CREATE TABLE IF NOT EXISTS lots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      lot_no TEXT NOT NULL,
      item_id INTEGER NOT NULL,
      work_order_id INTEGER,
      parent_lot_id INTEGER,
      qty REAL NOT NULL DEFAULT 0,
      unit TEXT NOT NULL DEFAULT 'EA',
      status TEXT NOT NULL DEFAULT 'CREATED',
      produced_at TEXT,
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (item_id) REFERENCES items(id),
      FOREIGN KEY (work_order_id) REFERENCES work_orders(id),
      FOREIGN KEY (parent_lot_id) REFERENCES lots(id),
      CONSTRAINT uniq_company_lot_no UNIQUE (company_id, lot_no)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_lots_company_item
    ON lots (company_id, item_id);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_lots_company_created
    ON lots (company_id, created_at);
  `);

  // LOT 이벤트(선택)
  db.exec(`
    CREATE TABLE IF NOT EXISTS lot_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      lot_id INTEGER NOT NULL,
      event_type TEXT NOT NULL,
      qty REAL,
      unit TEXT,
      ref_entity TEXT,
      ref_id INTEGER,
      event_ts TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (lot_id) REFERENCES lots(id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_lot_events_company_ts
    ON lot_events (company_id, event_ts);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_lot_events_company_lot
    ON lot_events (company_id, lot_id);
  `);

  // LOT: 작업지시 연계
  db.exec(`
    CREATE TABLE IF NOT EXISTS work_order_lots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      work_order_id INTEGER NOT NULL,
      lot_id INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      FOREIGN KEY (work_order_id) REFERENCES work_orders(id),
      FOREIGN KEY (lot_id) REFERENCES lots(id),
      CONSTRAINT uniq_company_wo_lot UNIQUE (company_id, work_order_id, lot_id)
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_work_order_lots_company
    ON work_order_lots (company_id, work_order_id);
  `);

  // 리포트: KPI 캐시(운영 성능)
  db.exec(`
    CREATE TABLE IF NOT EXISTS report_kpi_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_id TEXT NOT NULL,
      report_name TEXT NOT NULL,
      from_date TEXT NOT NULL,
      to_date TEXT NOT NULL,
      params_json TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      CONSTRAINT uniq_report_kpi_cache UNIQUE (
        company_id,
        report_name,
        from_date,
        to_date,
        params_json
      )
    );
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_report_kpi_cache_lookup
    ON report_kpi_cache (company_id, report_name, expires_at);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_report_kpi_cache_company_expires
    ON report_kpi_cache (company_id, expires_at);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_report_kpi_cache_company_created
    ON report_kpi_cache (company_id, created_at);
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

const cleanupNonces = (cutoffEpochSec) => {
  if (!Number.isInteger(cutoffEpochSec)) return 0;
  const result = db
    .prepare('DELETE FROM telemetry_nonces WHERE ts < ?')
    .run(cutoffEpochSec);
  return result.changes || 0;
};

const countNonces = () => {
  const row = db.prepare('SELECT COUNT(1) AS cnt FROM telemetry_nonces').get();
  return row ? row.cnt : 0;
};

const countReportKpiCacheRows = ({ companyId }) => {
  if (!companyId) return 0;
  const row = db
    .prepare('SELECT COUNT(1) AS cnt FROM report_kpi_cache WHERE company_id = ?')
    .get(companyId);
  return row ? row.cnt : 0;
};

const purgeReportKpiCacheNow = ({ maxRowsPerCompany }) => {
  const nowEpoch = Math.floor(Date.now() / 1000);

  db.prepare('DELETE FROM report_kpi_cache WHERE CAST(expires_at AS INTEGER) <= ?').run(nowEpoch);

  if (!Number.isInteger(maxRowsPerCompany) || maxRowsPerCompany <= 0) {
    return;
  }

  const companies = db
    .prepare('SELECT DISTINCT company_id AS companyId FROM report_kpi_cache')
    .all();

  const pruneStmt = db.prepare(
    `DELETE FROM report_kpi_cache
     WHERE company_id = ?
       AND id NOT IN (
         SELECT id
         FROM report_kpi_cache
         WHERE company_id = ?
         ORDER BY created_at DESC, id DESC
         LIMIT ?
       )`
  );

  for (const row of companies) {
    pruneStmt.run(row.companyId, row.companyId, maxRowsPerCompany);
  }
};

module.exports = {
  db,
  init,
  insertAuditLog,
  getEquipmentByDeviceKey,
  cleanupNonces,
  countNonces,
  countReportKpiCacheRows,
  purgeReportKpiCacheNow,
};
