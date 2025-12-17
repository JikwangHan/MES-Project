const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const ERR = require('../constants/errors');

const router = express.Router();

const getEquipmentByCode = (companyId, code) =>
  db
    .prepare('SELECT id, company_id, code FROM equipments WHERE company_id = ? AND code = ?')
    .get(companyId, code);

// POST /api/v1/telemetry/events
router.post('/events', (req, res) => {
  const { equipmentCode, timestamp, eventType, payload } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole; // VIEWER도 허용 (장비/게이트웨이 역할 가정)

  if (!equipmentCode) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'telemetry_events',
      payload: { equipmentCode, reason: 'EQUIPMENT_CODE_REQUIRED' },
    });
    return res
      .status(400)
      .json(
        fail(
          ERR.TELEMETRY_EQUIPMENT_CODE_REQUIRED.code,
          ERR.TELEMETRY_EQUIPMENT_CODE_REQUIRED.message
        )
      );
  }

  const equipment = getEquipmentByCode(companyId, equipmentCode);
  if (!equipment) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'telemetry_events',
      payload: { equipmentCode, reason: 'EQUIPMENT_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(
        fail(
          ERR.TELEMETRY_EQUIPMENT_NOT_FOUND.code,
          ERR.TELEMETRY_EQUIPMENT_NOT_FOUND.message
        )
      );
  }

  const eventTs = timestamp || new Date().toISOString();
  let payloadJson = '{}';
  if (payload !== undefined && payload !== null) {
    if (typeof payload === 'string') {
      payloadJson = payload;
    } else {
      try {
        payloadJson = JSON.stringify(payload);
      } catch (e) {
        return res
          .status(400)
          .json(fail(ERR.VALIDATION_ERROR.code, 'payload를 JSON으로 직렬화할 수 없습니다.'));
      }
    }
  }

  const eventTypeValue = eventType || 'TELEMETRY';
  const now = new Date().toISOString();

  try {
    const stmt = db.prepare(`
      INSERT INTO telemetry_events (
        company_id, equipment_id, equipment_code, event_type, event_ts, payload_json, received_at
      )
      VALUES (@companyId, @equipmentId, @equipmentCode, @eventType, @eventTs, @payloadJson, @receivedAt)
    `);
    const result = stmt.run({
      companyId,
      equipmentId: equipment.id,
      equipmentCode,
      eventType: eventTypeValue,
      eventTs,
      payloadJson,
      receivedAt: now,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, equipment_id as equipmentId, equipment_code as equipmentCode,
                event_type as eventType, event_ts as eventTs, payload_json as payloadJson, received_at as receivedAt
         FROM telemetry_events WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'telemetry_events',
      entityId: result.lastInsertRowid,
      payload: { equipmentCode, eventType: eventTypeValue },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'telemetry_events',
      payload: { equipmentCode, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/telemetry/events?since=&limit=
router.get('/events', (req, res) => {
  const companyId = req.companyId;
  const { since, limit } = req.query;

  let limitValue = 50;
  if (limit !== undefined) {
    const parsed = Number(limit);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 200) {
      return res
        .status(400)
        .json(fail(ERR.TELEMETRY_LIMIT_INVALID.code, ERR.TELEMETRY_LIMIT_INVALID.message));
    }
    limitValue = parsed;
  }

  const params = [companyId];
  let sinceClause = '';
  if (since) {
    sinceClause = 'AND event_ts >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, equipment_id as equipmentId, equipment_code as equipmentCode,
              event_type as eventType, event_ts as eventTs, payload_json as payloadJson, received_at as receivedAt
       FROM telemetry_events
       WHERE company_id = ?
       ${sinceClause}
       ORDER BY event_ts DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

module.exports = router;
