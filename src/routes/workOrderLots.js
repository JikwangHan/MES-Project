const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const toId = (value) => {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
};

const getWorkOrder = (id) =>
  db.prepare('SELECT id, company_id FROM work_orders WHERE id = ?').get(id);
const getLot = (id) =>
  db.prepare('SELECT id, company_id FROM lots WHERE id = ?').get(id);

// POST /api/v1/work-orders/:workOrderId/lots/:lotId/link
router.post('/:workOrderId/lots/:lotId/link', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const workOrderId = toId(req.params.workOrderId);
  const lotId = toId(req.params.lotId);

  if (!workOrderId || !lotId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'work_order_lots',
      payload: { workOrderId: req.params.workOrderId, lotId: req.params.lotId, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'workOrderId와 lotId는 필수입니다.'));
  }

  const workOrder = getWorkOrder(workOrderId);
  if (!workOrder || workOrder.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'work_order_lots',
      payload: { workOrderId, lotId, reason: 'WO_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.WO_NOT_FOUND.code, ERR.WO_NOT_FOUND.message));
  }

  const lot = getLot(lotId);
  if (!lot || lot.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'work_order_lots',
      payload: { workOrderId, lotId, reason: 'LOT_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.LOT_NOT_FOUND.code, ERR.LOT_NOT_FOUND.message));
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO work_order_lots (company_id, work_order_id, lot_id)
         VALUES (@companyId, @workOrderId, @lotId)`
      )
      .run({
        companyId,
        workOrderId,
        lotId,
      });

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'work_order_lots',
      entityId: result.lastInsertRowid,
      payload: { workOrderId, lotId },
    });

    return res.status(201).json(ok({ id: result.lastInsertRowid, workOrderId, lotId }));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'work_order_lots',
        payload: { workOrderId, lotId, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.WO_LOT_LINK_DUPLICATE.code, ERR.WO_LOT_LINK_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

module.exports = router;
