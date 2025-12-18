const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const toId = (value) => {
  if (value === undefined || value === null) return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
};

const getItemById = (id) =>
  db.prepare('SELECT id, company_id FROM items WHERE id = ?').get(id);
const getItemByCode = (companyId, code) =>
  db.prepare('SELECT id, company_id FROM items WHERE company_id = ? AND code = ?').get(companyId, code);
const getWorkOrderById = (id) =>
  db.prepare('SELECT id, company_id FROM work_orders WHERE id = ?').get(id);
const getLotByNo = (companyId, lotNo) =>
  db.prepare('SELECT id, company_id FROM lots WHERE company_id = ? AND lot_no = ?').get(companyId, lotNo);

// GET /api/v1/lots/:lotNo/trace
router.get('/:lotNo/trace', (req, res) => {
  const companyId = req.companyId;
  const lotNo = req.params.lotNo;
  const direction = (req.query.direction || 'down').toLowerCase();
  const depthRaw = req.query.depth;
  let depthValue = 3;

  if (depthRaw !== undefined) {
    const parsed = Number(depthRaw);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 10) {
      return res
        .status(400)
        .json(fail(ERR.LOT_TRACE_INVALID.code, ERR.LOT_TRACE_INVALID.message));
    }
    depthValue = parsed;
  }

  if (direction !== 'down' && direction !== 'up') {
    return res
      .status(400)
      .json(fail(ERR.LOT_TRACE_INVALID.code, ERR.LOT_TRACE_INVALID.message));
  }

  const root = db
    .prepare(
      `SELECT id, lot_no as lotNo, parent_lot_id as parentLotId, item_id as itemId,
              qty, unit, status, produced_at as producedAt, created_at as createdAt
       FROM lots WHERE company_id = ? AND lot_no = ?`
    )
    .get(companyId, lotNo);

  if (!root) {
    return res.status(404).json(fail(ERR.LOT_NOT_FOUND.code, ERR.LOT_NOT_FOUND.message));
  }

  let rows = [];
  if (direction === 'down') {
    rows = db
      .prepare(
        `WITH RECURSIVE trace(id, lot_no, parent_lot_id, item_id, qty, unit, status, produced_at, created_at, depth) AS (
           SELECT id, lot_no, parent_lot_id, item_id, qty, unit, status, produced_at, created_at, 0
           FROM lots
           WHERE company_id = ? AND lot_no = ?
           UNION ALL
           SELECT l.id, l.lot_no, l.parent_lot_id, l.item_id, l.qty, l.unit, l.status, l.produced_at, l.created_at, t.depth + 1
           FROM lots l
           JOIN trace t ON l.parent_lot_id = t.id
           WHERE l.company_id = ? AND t.depth < ?
         )
         SELECT id, lot_no as lotNo, parent_lot_id as parentLotId, item_id as itemId,
                qty, unit, status, produced_at as producedAt, created_at as createdAt, depth
         FROM trace
         ORDER BY depth, id`
      )
      .all(companyId, lotNo, companyId, depthValue);
  } else {
    rows = db
      .prepare(
        `WITH RECURSIVE trace(id, lot_no, parent_lot_id, item_id, qty, unit, status, produced_at, created_at, depth) AS (
           SELECT id, lot_no, parent_lot_id, item_id, qty, unit, status, produced_at, created_at, 0
           FROM lots
           WHERE company_id = ? AND lot_no = ?
           UNION ALL
           SELECT l.id, l.lot_no, l.parent_lot_id, l.item_id, l.qty, l.unit, l.status, l.produced_at, l.created_at, t.depth + 1
           FROM lots l
           JOIN trace t ON l.id = t.parent_lot_id
           WHERE l.company_id = ? AND t.depth < ?
         )
         SELECT id, lot_no as lotNo, parent_lot_id as parentLotId, item_id as itemId,
                qty, unit, status, produced_at as producedAt, created_at as createdAt, depth
         FROM trace
         ORDER BY depth DESC, id`
      )
      .all(companyId, lotNo, companyId, depthValue);
  }

  return res.json(ok({ root, nodes: rows }));
});

// GET /api/v1/lots/:lotNo
router.get('/:lotNo', (req, res) => {
  const companyId = req.companyId;
  const lotNo = req.params.lotNo;

  const row = db
    .prepare(
      `SELECT id, lot_no as lotNo, item_id as itemId, work_order_id as workOrderId,
              parent_lot_id as parentLotId, qty, unit, status,
              produced_at as producedAt, notes, created_at as createdAt
       FROM lots WHERE company_id = ? AND lot_no = ?`
    )
    .get(companyId, lotNo);

  if (!row) {
    return res.status(404).json(fail(ERR.LOT_NOT_FOUND.code, ERR.LOT_NOT_FOUND.message));
  }

  return res.json(ok(row));
});

// GET /api/v1/lots
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const { lotNo, itemCode, limit } = req.query;

  let limitValue = 50;
  if (limit !== undefined) {
    const parsed = Number(limit);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 200) {
      return res
        .status(400)
        .json(fail(ERR.VALIDATION_ERROR.code, 'limit 값이 올바르지 않습니다.'));
    }
    limitValue = parsed;
  }

  let itemId = null;
  if (itemCode) {
    const item = getItemByCode(companyId, itemCode);
    if (!item) {
      return res
        .status(400)
        .json(fail(ERR.LOT_ITEM_NOT_FOUND.code, ERR.LOT_ITEM_NOT_FOUND.message));
    }
    itemId = item.id;
  }

  const params = [companyId];
  let where = 'company_id = ?';
  if (lotNo) {
    where += ' AND lot_no = ?';
    params.push(lotNo);
  }
  if (itemId) {
    where += ' AND item_id = ?';
    params.push(itemId);
  }

  const rows = db
    .prepare(
      `SELECT id, lot_no as lotNo, item_id as itemId, work_order_id as workOrderId,
              parent_lot_id as parentLotId, qty, unit, status,
              produced_at as producedAt, notes, created_at as createdAt
       FROM lots
       WHERE ${where}
       ORDER BY created_at DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

// POST /api/v1/lots
router.post('/', ensureNotViewer, (req, res) => {
  const {
    lotNo,
    itemId,
    parentLotNo,
    workOrderId,
    qty,
    unit,
    status,
    producedAt,
    notes,
  } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  const itemIdValue = toId(itemId);
  const workOrderIdValue = toId(workOrderId);
  const qtyValue = Number(qty);

  if (!lotNo || !itemIdValue || !Number.isFinite(qtyValue) || qtyValue < 0) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'lots',
      payload: { lotNo, itemId, qty, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'lotNo, itemId, qty는 필수입니다.'));
  }

  const item = getItemById(itemIdValue);
  if (!item || item.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'lots',
      payload: { lotNo, itemId: itemIdValue, reason: 'ITEM_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.LOT_ITEM_NOT_FOUND.code, ERR.LOT_ITEM_NOT_FOUND.message));
  }

  if (workOrderIdValue) {
    const workOrder = getWorkOrderById(workOrderIdValue);
    if (!workOrder || workOrder.company_id !== companyId) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'lots',
        payload: { lotNo, workOrderId: workOrderIdValue, reason: 'WORK_ORDER_NOT_FOUND' },
      });
      return res
        .status(400)
        .json(fail(ERR.LOT_WORK_ORDER_NOT_FOUND.code, ERR.LOT_WORK_ORDER_NOT_FOUND.message));
    }
  }

  let parentLotId = null;
  if (parentLotNo) {
    const parent = getLotByNo(companyId, parentLotNo);
    if (!parent || parent.company_id !== companyId) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'lots',
        payload: { lotNo, parentLotNo, reason: 'PARENT_NOT_FOUND' },
      });
      return res
        .status(400)
        .json(fail(ERR.LOT_PARENT_NOT_FOUND.code, ERR.LOT_PARENT_NOT_FOUND.message));
    }
    parentLotId = parent.id;
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO lots
         (company_id, lot_no, item_id, work_order_id, parent_lot_id, qty, unit, status, produced_at, notes)
         VALUES (@companyId, @lotNo, @itemId, @workOrderId, @parentLotId, @qty, @unit, @status, @producedAt, @notes)`
      )
      .run({
        companyId,
        lotNo,
        itemId: itemIdValue,
        workOrderId: workOrderIdValue,
        parentLotId,
        qty: qtyValue,
        unit: unit || 'EA',
        status: status || 'CREATED',
        producedAt: producedAt || null,
        notes: notes || null,
      });

    const created = db
      .prepare(
        `SELECT id, lot_no as lotNo, item_id as itemId, work_order_id as workOrderId,
                parent_lot_id as parentLotId, qty, unit, status,
                produced_at as producedAt, notes, created_at as createdAt
         FROM lots WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'lots',
      entityId: result.lastInsertRowid,
      payload: { lotNo, itemId: itemIdValue, parentLotNo },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'lots',
        payload: { lotNo, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.LOT_NO_DUPLICATE.code, ERR.LOT_NO_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

module.exports = router;
