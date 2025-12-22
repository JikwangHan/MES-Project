const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');
const { encryptSecret } = require('../utils/crypto');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');

const router = express.Router();

const getStaleMinutes = () => {
  const value = Number(process.env.TELEMETRY_STALE_MIN || 5);
  return Number.isFinite(value) && value > 0 ? value : 5;
};

const calcStatus = (lastSeenAt, staleMinutes) => {
  if (!lastSeenAt) return 'NEVER';
  const last = new Date(lastSeenAt);
  if (Number.isNaN(last.getTime())) return 'NEVER';
  const diffMin = (Date.now() - last.getTime()) / 60000;
  return diffMin > staleMinutes ? 'WARNING' : 'OK';
};

const getProcess = (id) =>
  db.prepare('SELECT id, company_id FROM processes WHERE id = ?').get(id);

// POST /api/v1/equipments
router.post('/', ensureNotViewer, (req, res) => {
  const { name, code, processId, commType, commConfig, isActive } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'equipments',
      payload: { name, code, processId, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'name, code는 필수이며 processId는 선택입니다.'));
  }

  if (processId) {
    const proc = getProcess(processId);
    if (!proc || proc.company_id !== companyId) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'equipments',
        payload: { name, code, processId, reason: 'PROCESS_NOT_FOUND' },
      });
      return res
        .status(400)
        .json(fail(ERR.EQUIPMENT_PROCESS_NOT_FOUND.code, ERR.EQUIPMENT_PROCESS_NOT_FOUND.message));
    }
  }

  // comm_config_json: 객체면 문자열로, 문자열이면 그대로 저장
  let commConfigJson = null;
  if (commConfig !== undefined && commConfig !== null) {
    if (typeof commConfig === 'string') {
      commConfigJson = commConfig;
    } else {
      try {
        commConfigJson = JSON.stringify(commConfig);
      } catch (e) {
        return res.status(400).json(fail(ERR.VALIDATION_ERROR.code, 'commConfig를 JSON으로 직렬화할 수 없습니다.'));
      }
    }
  }

  const isActiveValue = typeof isActive === 'number' ? isActive : 1;

  try {
    const stmt = db.prepare(`
      INSERT INTO equipments (company_id, name, code, process_id, comm_type, comm_config_json, is_active, created_by_role)
      VALUES (@companyId, @name, @code, @processId, @commType, @commConfigJson, @isActive, @role)
    `);
    const result = stmt.run({
      companyId,
      name,
      code,
      processId: processId || null,
      commType: commType || null,
      commConfigJson,
      isActive: isActiveValue,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, name, code, process_id as processId,
                comm_type as commType, comm_config_json as commConfigJson,
                is_active as isActive, created_at as createdAt
         FROM equipments WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'equipments',
      entityId: result.lastInsertRowid,
      payload: { name, code, processId: processId || null, commType: commType || null },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'equipments',
        payload: { name, code, processId, reason: 'EQUIPMENT_CODE_DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.EQUIPMENT_CODE_DUPLICATE.code, ERR.EQUIPMENT_CODE_DUPLICATE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'equipments',
      payload: { name, code, processId, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/equipments
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const staleMinutes = getStaleMinutes();
  const statusFilter = String(req.query.status || '').toUpperCase();
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, process_id as processId,
              comm_type as commType, comm_config_json as commConfigJson,
              is_active as isActive, created_at as createdAt,
              device_key_id as deviceKeyId,
              device_key_last_seen_at as lastSeenAt
       FROM equipments
       WHERE company_id = ?
       ORDER BY id`
    )
    .all(companyId);
  const items = rows.map((row) => ({
    ...row,
    status: calcStatus(row.lastSeenAt, staleMinutes),
  }));
  const filtered = ['OK', 'WARNING', 'NEVER'].includes(statusFilter)
    ? items.filter((item) => item.status === statusFilter)
    : items;
  return res.json(ok(filtered));
});

// GET /api/v1/equipments/:id/telemetry?limit=
router.get('/:id/telemetry', (req, res) => {
  const companyId = req.companyId;
  const equipmentId = Number(req.params.id);
  if (!Number.isInteger(equipmentId) || equipmentId <= 0) {
    return res.status(400).json(fail(ERR.VALIDATION_ERROR.code, 'equipmentId가 올바르지 않습니다.'));
  }

  const equipment = db
    .prepare('SELECT id, company_id as companyId FROM equipments WHERE id = ?')
    .get(equipmentId);
  if (!equipment || equipment.companyId !== companyId) {
    return res.status(404).json(fail(ERR.NOT_FOUND.code, ERR.NOT_FOUND.message));
  }

  let limitValue = 20;
  if (req.query.limit !== undefined) {
    const parsed = Number(req.query.limit);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 100) {
      return res
        .status(400)
        .json(fail(ERR.TELEMETRY_LIMIT_INVALID.code, ERR.TELEMETRY_LIMIT_INVALID.message));
    }
    limitValue = parsed;
  }

  const rows = db
    .prepare(
      `SELECT event_ts as eventTs, payload_json as payloadJson
       FROM telemetry_events
       WHERE company_id = ? AND equipment_id = ?
       ORDER BY event_ts DESC
       LIMIT ?`
    )
    .all(companyId, equipmentId, limitValue);

  const items = rows.map((row) => {
    let metricCount = 0;
    try {
      const payload = JSON.parse(row.payloadJson || '{}');
      if (Array.isArray(payload)) {
        metricCount = payload.length;
      } else if (payload && typeof payload === 'object') {
        if (Array.isArray(payload.metrics)) {
          metricCount = payload.metrics.length;
        } else if (payload.metrics && typeof payload.metrics === 'object') {
          metricCount = Object.keys(payload.metrics).length;
        }
      }
    } catch (err) {
      metricCount = 0;
    }
    return { eventTs: row.eventTs, metricCount };
  });

  return res.json(ok(items));
});

// POST /api/v1/equipments/:id/device-key
router.post('/:id/device-key', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const equipmentId = Number(req.params.id);

  const equipment = db
    .prepare('SELECT id, company_id FROM equipments WHERE id = ?')
    .get(equipmentId);

  if (!equipment || equipment.company_id !== companyId) {
    return res.status(404).json(fail(ERR.NOT_FOUND.code, ERR.NOT_FOUND.message));
  }

  const deviceKeyId = uuidv4();
  const deviceSecret = crypto.randomBytes(32).toString('hex');
  const encryptedSecret = encryptSecret(deviceSecret);
  const issuedAt = new Date().toISOString();

  db.prepare(
    `UPDATE equipments
     SET device_key_id = @deviceKeyId,
         device_key_secret_enc = @encryptedSecret,
         device_key_status = 'ACTIVE',
         device_key_issued_at = @issuedAt,
         device_key_last_seen_at = NULL
     WHERE id = @equipmentId`
  ).run({
    deviceKeyId,
    encryptedSecret,
    issuedAt,
    equipmentId,
  });

  insertAuditLog({
    companyId,
    actorRole: role,
    action: 'UPDATE',
    entity: 'equipments',
    entityId: equipmentId,
    payload: { deviceKeyId, issuedAt },
  });

  // secret은 1회만 노출
  return res.status(201).json(ok({ deviceKeyId, deviceSecret, issuedAt }));
});

// POST /api/v1/equipments/:id/device-key/rotate
router.post('/:id/device-key/rotate', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const equipmentId = Number(req.params.id);

  const equipment = db
    .prepare('SELECT id, company_id, device_key_id FROM equipments WHERE id = ?')
    .get(equipmentId);

  if (!equipment || equipment.company_id !== companyId) {
    return res.status(404).json(fail(ERR.NOT_FOUND.code, ERR.NOT_FOUND.message));
  }

  const prevDeviceKeyId = equipment.device_key_id || null;
  const deviceKeyId = uuidv4();
  const deviceSecret = crypto.randomBytes(32).toString('hex');
  const encryptedSecret = encryptSecret(deviceSecret);
  const issuedAt = new Date().toISOString();

  db.prepare(
    `UPDATE equipments
     SET device_key_id = @deviceKeyId,
         device_key_secret_enc = @encryptedSecret,
         device_key_status = 'ACTIVE',
         device_key_issued_at = @issuedAt
     WHERE id = @equipmentId`
  ).run({
    deviceKeyId,
    encryptedSecret,
    issuedAt,
    equipmentId,
  });

  insertAuditLog({
    companyId,
    actorRole: role,
    action: 'UPDATE',
    entity: 'equipments',
    entityId: equipmentId,
    payload: { deviceKeyId, issuedAt, prevDeviceKeyId, action: 'ROTATE' },
  });

  return res
    .status(200)
    .json(ok({ deviceKeyId, deviceSecret, deviceKeySecret: deviceSecret, issuedAt }));
});

// POST /api/v1/equipments/:id/device-key/revoke
router.post('/:id/device-key/revoke', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const equipmentId = Number(req.params.id);

  const equipment = db
    .prepare('SELECT id, company_id, device_key_id FROM equipments WHERE id = ?')
    .get(equipmentId);

  if (!equipment || equipment.company_id !== companyId) {
    return res.status(404).json(fail(ERR.NOT_FOUND.code, ERR.NOT_FOUND.message));
  }

  if (!equipment.device_key_id) {
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'device_key가 발급되지 않았습니다.'));
  }

  db.prepare(
    `UPDATE equipments
     SET device_key_status = 'REVOKED'
     WHERE id = @equipmentId`
  ).run({ equipmentId });

  insertAuditLog({
    companyId,
    actorRole: role,
    action: 'UPDATE',
    entity: 'equipments',
    entityId: equipmentId,
    payload: { deviceKeyId: equipment.device_key_id, action: 'REVOKE' },
  });

  return res.status(200).json(ok({ deviceKeyId: equipment.device_key_id, status: 'REVOKED' }));
});

module.exports = router;
