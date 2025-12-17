const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

// POST /api/v1/items
router.post('/', ensureNotViewer, (req, res) => {
  const { categoryId, name, code } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!categoryId || !name || !code) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'items',
      payload: { categoryId, name, code, reason: 'VALIDATION' },
    });
    return res.status(400).json(fail(ERR.VALIDATION_ERROR.code, 'categoryId, name, code는 필수입니다.'));
  }

  // 카테고리 존재 및 동일 회사 확인
  const categoryRow = db
    .prepare('SELECT id, company_id FROM item_categories WHERE id = ?')
    .get(categoryId);
  if (!categoryRow) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'items',
      payload: { categoryId, name, code, reason: 'CATEGORY_NOT_FOUND' },
    });
    return res.status(400).json(fail(ERR.CATEGORY_NOT_FOUND.code, ERR.CATEGORY_NOT_FOUND.message));
  }
  if (categoryRow.company_id !== companyId) {
    // 회사가 다른 categoryId는 "잘못된 입력"으로 동일하게 처리(정보 노출 방지)
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'items',
      payload: { categoryId, name, code, reason: 'CATEGORY_NOT_FOUND' },
    });
    return res.status(400).json(fail(ERR.CATEGORY_NOT_FOUND.code, ERR.CATEGORY_NOT_FOUND.message));
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO items (company_id, category_id, name, code, created_by_role)
      VALUES (@companyId, @categoryId, @name, @code, @role)
    `);
    const result = stmt.run({
      companyId,
      categoryId,
      name,
      code,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, category_id as categoryId, name, code, created_at as createdAt
         FROM items WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'items',
      entityId: result.lastInsertRowid,
      payload: { categoryId, name, code },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'items',
        payload: { categoryId, name, code, reason: 'DUPLICATE_CODE' },
      });
      return res.status(409).json(fail(ERR.DUPLICATE_CODE.code, ERR.DUPLICATE_CODE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'items',
      payload: { categoryId, name, code, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/items
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const rows = db
    .prepare(
      `SELECT
         i.id,
         i.company_id as companyId,
         i.category_id as categoryId,
         i.name,
         i.code,
         i.created_at as createdAt
       FROM items i
       WHERE i.company_id = ?
       ORDER BY i.id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
