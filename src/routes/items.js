const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');

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
    return res
      .status(400)
      .json(fail('VALIDATION_ERROR', 'categoryId, name, code는 필수입니다.'));
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
    return res
      .status(400)
      .json(fail('CATEGORY_NOT_FOUND', 'categoryId가 존재하지 않습니다.'));
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
    return res
      .status(400)
      .json(fail('CATEGORY_NOT_FOUND', 'categoryId가 존재하지 않습니다.'));
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
      return res.status(409).json(fail('DUPLICATE_CODE', '동일 코드가 이미 존재합니다.'));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'items',
      payload: { categoryId, name, code, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail('SERVER_ERROR', '서버 오류가 발생했습니다.'));
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
