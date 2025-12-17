const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

// 유틸: 공정 존재/회사 확인
const getProcess = (id) =>
  db.prepare('SELECT id, company_id FROM processes WHERE id = ?').get(id);

// POST /api/v1/processes
router.post('/', ensureNotViewer, (req, res) => {
  const { name, code, parentId, sortOrder } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'processes',
      payload: { name, code, parentId, sortOrder, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(
        fail(ERR.VALIDATION_ERROR.code, 'name, code는 필수이며 parentId는 선택입니다.')
      );
  }

  // parent 확인 (있으면 동일 회사, 존재해야 함)
  if (parentId) {
    const parent = getProcess(parentId);
    if (!parent || parent.company_id !== companyId) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'processes',
        payload: { name, code, parentId, sortOrder, reason: 'PARENT_NOT_FOUND' },
      });
      return res
        .status(400)
        .json(fail(ERR.PROCESS_PARENT_NOT_FOUND.code, ERR.PROCESS_PARENT_NOT_FOUND.message));
    }
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO processes (company_id, name, code, parent_id, sort_order, created_by_role)
      VALUES (@companyId, @name, @code, @parentId, @sortOrder, @role)
    `);
    const result = stmt.run({
      companyId,
      name,
      code,
      parentId: parentId || null,
      sortOrder: sortOrder ?? 0,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, name, code, parent_id as parentId,
                sort_order as sortOrder, created_at as createdAt
         FROM processes WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'processes',
      entityId: result.lastInsertRowid,
      payload: { name, code, parentId: parentId || null, sortOrder: sortOrder ?? 0 },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'processes',
        payload: { name, code, parentId, sortOrder, reason: 'PROCESS_CODE_DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.PROCESS_CODE_DUPLICATE.code, ERR.PROCESS_CODE_DUPLICATE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'processes',
      payload: { name, code, parentId, sortOrder, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/processes
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, parent_id as parentId,
              sort_order as sortOrder, created_at as createdAt
       FROM processes
       WHERE company_id = ?
       ORDER BY sort_order, id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
