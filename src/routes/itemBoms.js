const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router({ mergeParams: true });

// 유틸: 동일 회사의 item인지 확인
const getItemOwnedByCompany = (id, companyId) => {
  return db
    .prepare('SELECT id, company_id FROM items WHERE id = ?')
    .get(id);
};

// POST /api/v1/items/:itemId/parts
router.post('/', ensureNotViewer, (req, res) => {
  const parentId = Number(req.params.itemId);
  const { childItemId, qty, unit } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!parentId || !childItemId || !qty || Number(qty) <= 0) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'item_boms',
      payload: { parentId, childItemId, qty, unit, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'childItemId, qty>0 는 필수입니다.'));
  }

  // parent / child 소유권 확인
  const parent = getItemOwnedByCompany(parentId, companyId);
  const child = getItemOwnedByCompany(childItemId, companyId);

  if (!parent || parent.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'item_boms',
      payload: { parentId, childItemId, qty, unit, reason: 'PARENT_NOT_FOUND' },
    });
    return res.status(400).json(fail(ERR.ITEM_NOT_FOUND.code, ERR.ITEM_NOT_FOUND.message));
  }

  if (!child || child.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'item_boms',
      payload: { parentId, childItemId, qty, unit, reason: 'CHILD_NOT_FOUND' },
    });
    return res.status(400).json(fail(ERR.ITEM_NOT_FOUND.code, ERR.ITEM_NOT_FOUND.message));
  }

  if (parentId === childItemId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'item_boms',
      payload: { parentId, childItemId, qty, unit, reason: 'SELF_REFERENCE' },
    });
    return res.status(400).json(fail(ERR.BOM_SELF_REFERENCE.code, ERR.BOM_SELF_REFERENCE.message));
  }

  try {
    const stmt = db.prepare(`
      INSERT INTO item_boms (company_id, parent_item_id, child_item_id, qty, unit, created_by_role)
      VALUES (@companyId, @parentId, @childItemId, @qty, @unit, @role)
    `);
    const result = stmt.run({
      companyId,
      parentId,
      childItemId,
      qty,
      unit: unit || null,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, parent_item_id as parentItemId, child_item_id as childItemId,
                qty, unit, created_at as createdAt
         FROM item_boms WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'item_boms',
      entityId: result.lastInsertRowid,
      payload: { parentId, childItemId, qty, unit: unit || null },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'item_boms',
        payload: { parentId, childItemId, qty, unit, reason: 'BOM_DUPLICATE' },
      });
      return res.status(409).json(fail(ERR.BOM_DUPLICATE.code, ERR.BOM_DUPLICATE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'item_boms',
      payload: { parentId, childItemId, qty, unit, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/items/:itemId/parts
router.get('/', (req, res) => {
  const parentId = Number(req.params.itemId);
  const companyId = req.companyId;

  const parent = getItemOwnedByCompany(parentId, companyId);
  if (!parent || parent.company_id !== companyId) {
    return res.status(400).json(fail(ERR.ITEM_NOT_FOUND.code, ERR.ITEM_NOT_FOUND.message));
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, parent_item_id as parentItemId,
              child_item_id as childItemId, qty, unit, created_at as createdAt
       FROM item_boms
       WHERE company_id = ? AND parent_item_id = ?
       ORDER BY id`
    )
    .all(companyId, parentId);
  return res.json(ok(rows));
});

// DELETE /api/v1/items/:itemId/parts/:partId
router.delete('/:partId', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const parentId = Number(req.params.itemId);
  const partId = Number(req.params.partId);

  const part = db
    .prepare(
      `SELECT id, company_id as companyId, parent_item_id as parentItemId, child_item_id as childItemId
       FROM item_boms WHERE id = ? AND parent_item_id = ?`
    )
    .get(partId, parentId);

  if (!part || part.companyId !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'DELETE_FAIL',
      entity: 'item_boms',
      payload: { partId, parentId, reason: 'NOT_FOUND' },
    });
    return res.status(400).json(fail(ERR.ITEM_NOT_FOUND.code, ERR.ITEM_NOT_FOUND.message));
  }

  db.prepare('DELETE FROM item_boms WHERE id = ?').run(partId);

  insertAuditLog({
    companyId,
    actorRole: role,
    action: 'DELETE',
    entity: 'item_boms',
    entityId: partId,
    payload: { parentId, childItemId: part.childItemId },
  });

  return res.json(ok({ deleted: true }));
});

module.exports = router;
