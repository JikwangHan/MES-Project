const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const VALID_STATUSES = new Set([
  'PLANNED',
  'RELEASED',
  'RUNNING',
  'DONE',
  'CANCELED',
]);

const getItem = (id) =>
  db.prepare('SELECT id, company_id FROM items WHERE id = ?').get(id);
const getProcess = (id) =>
  db.prepare('SELECT id, company_id FROM processes WHERE id = ?').get(id);
const getEquipment = (id) =>
  db.prepare('SELECT id, company_id FROM equipments WHERE id = ?').get(id);

// POST /api/v1/work-orders
router.post('/', ensureNotViewer, (req, res) => {
  const {
    woNo,
    itemId,
    processId,
    equipmentId,
    planQty,
    status,
    scheduledStartAt,
    scheduledEndAt,
  } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!woNo || !itemId || !processId || !planQty || Number(planQty) <= 0) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'work_orders',
      payload: { woNo, itemId, processId, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'woNo, itemId, processId, planQty는 필수입니다.'));
  }

  const statusValue = status || 'PLANNED';
  if (!VALID_STATUSES.has(statusValue)) {
    return res
      .status(400)
      .json(fail(ERR.WORK_ORDER_STATUS_INVALID.code, ERR.WORK_ORDER_STATUS_INVALID.message));
  }

  const item = getItem(itemId);
  const process = getProcess(processId);
  const equipment = equipmentId ? getEquipment(equipmentId) : null;

  if (
    !item ||
    item.company_id !== companyId ||
    !process ||
    process.company_id !== companyId ||
    (equipmentId && (!equipment || equipment.company_id !== companyId))
  ) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'work_orders',
      payload: { woNo, itemId, processId, equipmentId, reason: 'REF_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.WORK_ORDER_REF_NOT_FOUND.code, ERR.WORK_ORDER_REF_NOT_FOUND.message));
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO work_orders
         (company_id, wo_no, item_id, process_id, equipment_id, plan_qty, status, scheduled_start_at, scheduled_end_at)
         VALUES (@companyId, @woNo, @itemId, @processId, @equipmentId, @planQty, @status, @scheduledStartAt, @scheduledEndAt)`
      )
      .run({
        companyId,
        woNo,
        itemId,
        processId,
        equipmentId: equipmentId || null,
        planQty: Number(planQty),
        status: statusValue,
        scheduledStartAt: scheduledStartAt || null,
        scheduledEndAt: scheduledEndAt || null,
      });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, wo_no as woNo, item_id as itemId,
                process_id as processId, equipment_id as equipmentId, plan_qty as planQty,
                status, scheduled_start_at as scheduledStartAt, scheduled_end_at as scheduledEndAt,
                created_at as createdAt
         FROM work_orders WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'work_orders',
      entityId: result.lastInsertRowid,
      payload: { woNo, status: statusValue },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res
        .status(409)
        .json(fail(ERR.WORK_ORDER_NO_DUPLICATE.code, ERR.WORK_ORDER_NO_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/work-orders
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const { status, since, limit } = req.query;

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

  const params = [companyId];
  let where = 'company_id = ?';
  if (status) {
    where += ' AND status = ?';
    params.push(status);
  }
  if (since) {
    where += ' AND created_at >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, wo_no as woNo, item_id as itemId,
              process_id as processId, equipment_id as equipmentId, plan_qty as planQty,
              status, scheduled_start_at as scheduledStartAt, scheduled_end_at as scheduledEndAt,
              created_at as createdAt
       FROM work_orders
       WHERE ${where}
       ORDER BY id DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

// POST /api/v1/work-orders/:id/results
router.post('/:id/results', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const workOrderId = Number(req.params.id);
  const { goodQty, defectQty, eventTs, note } = req.body || {};

  if (
    goodQty === undefined ||
    defectQty === undefined ||
    Number(goodQty) < 0 ||
    Number(defectQty) < 0
  ) {
    return res
      .status(400)
      .json(fail(ERR.RESULT_QTY_INVALID.code, ERR.RESULT_QTY_INVALID.message));
  }

  const workOrder = db
    .prepare('SELECT id, company_id FROM work_orders WHERE id = ?')
    .get(workOrderId);

  if (!workOrder || workOrder.company_id !== companyId) {
    return res
      .status(400)
      .json(fail(ERR.WORK_ORDER_REF_NOT_FOUND.code, ERR.WORK_ORDER_REF_NOT_FOUND.message));
  }

  const eventTsValue = eventTs || new Date().toISOString();

  const result = db
    .prepare(
      `INSERT INTO production_results
       (company_id, work_order_id, good_qty, defect_qty, event_ts, note)
       VALUES (@companyId, @workOrderId, @goodQty, @defectQty, @eventTs, @note)`
    )
    .run({
      companyId,
      workOrderId,
      goodQty: Number(goodQty),
      defectQty: Number(defectQty),
      eventTs: eventTsValue,
      note: note || null,
    });

  const created = db
    .prepare(
      `SELECT id, company_id as companyId, work_order_id as workOrderId,
              good_qty as goodQty, defect_qty as defectQty,
              event_ts as eventTs, note, created_at as createdAt
       FROM production_results WHERE id = ?`
    )
    .get(result.lastInsertRowid);

  insertAuditLog({
    companyId,
    actorRole: role,
    action: 'CREATE',
    entity: 'production_results',
    entityId: result.lastInsertRowid,
    payload: { workOrderId, goodQty, defectQty },
  });

  return res.status(201).json(ok(created));
});

// GET /api/v1/work-orders/:id/results
router.get('/:id/results', (req, res) => {
  const companyId = req.companyId;
  const workOrderId = Number(req.params.id);
  const { since, limit } = req.query;

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

  const workOrder = db
    .prepare('SELECT id, company_id FROM work_orders WHERE id = ?')
    .get(workOrderId);
  if (!workOrder || workOrder.company_id !== companyId) {
    return res
      .status(400)
      .json(fail(ERR.WORK_ORDER_REF_NOT_FOUND.code, ERR.WORK_ORDER_REF_NOT_FOUND.message));
  }

  const params = [companyId, workOrderId];
  let sinceClause = '';
  if (since) {
    sinceClause = 'AND event_ts >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, work_order_id as workOrderId,
              good_qty as goodQty, defect_qty as defectQty,
              event_ts as eventTs, note, created_at as createdAt
       FROM production_results
       WHERE company_id = ? AND work_order_id = ?
       ${sinceClause}
       ORDER BY event_ts DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

module.exports = router;
