const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');

const router = express.Router();

// POST /api/v1/item-categories
router.post('/', ensureNotViewer, (req, res) => {
  const { name, code, parentId } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code) {
    return res.status(400).json(fail('VALIDATION_ERROR', 'name, code는 필수입니다.'));
  }

  // 부모 존재 여부 및 같은 회사인지 확인
  let parentRow = null;
  if (parentId) {
    parentRow = db
      .prepare('SELECT id, company_id FROM item_categories WHERE id = ?')
      .get(parentId);
    if (!parentRow) {
      return res.status(400).json(fail('PARENT_NOT_FOUND', 'parentId가 존재하지 않습니다.'));
    }
    if (parentRow.company_id !== companyId) {
      return res
        .status(403)
        .json(fail('FORBIDDEN', '다른 회사의 품목유형을 부모로 연결할 수 없습니다.'));
    }
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO item_categories (company_id, name, code, parent_id, created_by_role)
      VALUES (@companyId, @name, @code, @parentId, @role)
    `);
    const result = stmt.run({
      companyId,
      name,
      code,
      parentId: parentId || null,
      role,
    });

    const created = db
      .prepare(
        'SELECT id, company_id as companyId, name, code, parent_id as parentId, created_at as createdAt FROM item_categories WHERE id = ?'
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'item_categories',
      entityId: result.lastInsertRowid,
      payload: { name, code, parentId: parentId || null },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(409).json(fail('DUPLICATE_CODE', '동일 코드가 이미 존재합니다.'));
    }
    console.error(err);
    return res.status(500).json(fail('SERVER_ERROR', '서버 오류가 발생했습니다.'));
  }
});

// GET /api/v1/item-categories
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, parent_id as parentId, created_at as createdAt
       FROM item_categories
       WHERE company_id = ?
       ORDER BY id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
