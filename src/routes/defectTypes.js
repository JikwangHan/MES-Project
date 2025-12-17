const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const getProcess = (id) =>
  db.prepare('SELECT id, company_id FROM processes WHERE id = ?').get(id);

// POST /api/v1/defect-types
router.post('/', ensureNotViewer, (req, res) => {
  const { name, code, processId, severity, isActive } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'defect_types',
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
        entity: 'defect_types',
        payload: { name, code, processId, reason: 'PROCESS_NOT_FOUND' },
      });
      return res
        .status(400)
        .json(fail(ERR.DEFECT_PROCESS_NOT_FOUND.code, ERR.DEFECT_PROCESS_NOT_FOUND.message));
    }
  }

  const severityValue =
    typeof severity === 'number' && severity > 0 ? severity : 1;
  const isActiveValue = typeof isActive === 'number' ? isActive : 1;

  try {
    const stmt = db.prepare(`
      INSERT INTO defect_types (company_id, name, code, process_id, severity, is_active, created_by_role)
      VALUES (@companyId, @name, @code, @processId, @severity, @isActive, @role)
    `);
    const result = stmt.run({
      companyId,
      name,
      code,
      processId: processId || null,
      severity: severityValue,
      isActive: isActiveValue,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, name, code, process_id as processId,
                severity, is_active as isActive, created_at as createdAt
         FROM defect_types WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'defect_types',
      entityId: result.lastInsertRowid,
      payload: { name, code, processId: processId || null, severity: severityValue },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'defect_types',
        payload: { name, code, processId, reason: 'DEFECT_CODE_DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.DEFECT_CODE_DUPLICATE.code, ERR.DEFECT_CODE_DUPLICATE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'defect_types',
      payload: { name, code, processId, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/defect-types
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, process_id as processId,
              severity, is_active as isActive, created_at as createdAt
       FROM defect_types
       WHERE company_id = ?
       ORDER BY id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
