const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

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
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, process_id as processId,
              comm_type as commType, comm_config_json as commConfigJson,
              is_active as isActive, created_at as createdAt
       FROM equipments
       WHERE company_id = ?
       ORDER BY id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
