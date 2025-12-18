const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const VALID_TYPES = new Set(['INCOMING', 'IN_PROCESS', 'FINAL']);
const VALID_STATUSES = new Set(['PASS', 'FAIL', 'HOLD']);

const toId = (value) => {
  if (value === undefined || value === null) return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return parsed;
};

const getWorkOrder = (id) =>
  db.prepare('SELECT id, company_id FROM work_orders WHERE id = ?').get(id);
const getItem = (id) =>
  db.prepare('SELECT id, company_id FROM items WHERE id = ?').get(id);
const getProcess = (id) =>
  db.prepare('SELECT id, company_id FROM processes WHERE id = ?').get(id);
const getEquipment = (id) =>
  db.prepare('SELECT id, company_id FROM equipments WHERE id = ?').get(id);
const getInspection = (id) =>
  db
    .prepare('SELECT id, company_id FROM quality_inspections WHERE id = ?')
    .get(id);
const getDefectType = (id) =>
  db.prepare('SELECT id, company_id FROM defect_types WHERE id = ?').get(id);

// POST /api/v1/quality/inspections
router.post('/inspections', ensureNotViewer, (req, res) => {
  const {
    inspectionNo,
    workOrderId,
    itemId,
    processId,
    equipmentId,
    inspectionType,
    status,
    inspectedAt,
    inspectorName,
    note,
  } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!inspectionNo || !inspectionType || !status) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspections',
      payload: { inspectionNo, inspectionType, status, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'inspectionNo, inspectionType, status는 필수입니다.'));
  }

  if (!VALID_TYPES.has(inspectionType)) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspections',
      payload: { inspectionNo, inspectionType, reason: 'TYPE_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_TYPE_INVALID.code, ERR.QUALITY_INSPECTION_TYPE_INVALID.message));
  }

  if (!VALID_STATUSES.has(status)) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspections',
      payload: { inspectionNo, status, reason: 'STATUS_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_STATUS_INVALID.code, ERR.QUALITY_INSPECTION_STATUS_INVALID.message));
  }

  const workOrderIdValue = toId(workOrderId);
  const itemIdValue = toId(itemId);
  const processIdValue = toId(processId);
  const equipmentIdValue = toId(equipmentId);

  const workOrder = workOrderIdValue ? getWorkOrder(workOrderIdValue) : null;
  const item = itemIdValue ? getItem(itemIdValue) : null;
  const process = processIdValue ? getProcess(processIdValue) : null;
  const equipment = equipmentIdValue ? getEquipment(equipmentIdValue) : null;

  if (
    (workOrderIdValue && (!workOrder || workOrder.company_id !== companyId)) ||
    (itemIdValue && (!item || item.company_id !== companyId)) ||
    (processIdValue && (!process || process.company_id !== companyId)) ||
    (equipmentIdValue && (!equipment || equipment.company_id !== companyId))
  ) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspections',
      payload: {
        inspectionNo,
        workOrderId: workOrderIdValue,
        itemId: itemIdValue,
        processId: processIdValue,
        equipmentId: equipmentIdValue,
        reason: 'REF_NOT_FOUND',
      },
    });
    return res
      .status(400)
      .json(
        fail(ERR.QUALITY_INSPECTION_REF_NOT_FOUND.code, ERR.QUALITY_INSPECTION_REF_NOT_FOUND.message)
      );
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO quality_inspections
         (company_id, inspection_no, work_order_id, item_id, process_id, equipment_id,
          inspection_type, status, inspected_at, inspector_name, note)
         VALUES (@companyId, @inspectionNo, @workOrderId, @itemId, @processId, @equipmentId,
                 @inspectionType, @status, @inspectedAt, @inspectorName, @note)`
      )
      .run({
        companyId,
        inspectionNo,
        workOrderId: workOrderIdValue,
        itemId: itemIdValue,
        processId: processIdValue,
        equipmentId: equipmentIdValue,
        inspectionType,
        status,
        inspectedAt: inspectedAt || new Date().toISOString(),
        inspectorName: inspectorName || null,
        note: note || null,
      });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, inspection_no as inspectionNo,
                work_order_id as workOrderId, item_id as itemId, process_id as processId,
                equipment_id as equipmentId, inspection_type as inspectionType,
                status, inspected_at as inspectedAt, inspector_name as inspectorName,
                note, created_at as createdAt
         FROM quality_inspections WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'quality_inspections',
      entityId: result.lastInsertRowid,
      payload: { inspectionNo, inspectionType, status },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspections',
        payload: { inspectionNo, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(
          fail(
            ERR.QUALITY_INSPECTION_NO_DUPLICATE.code,
            ERR.QUALITY_INSPECTION_NO_DUPLICATE.message
          )
        );
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/quality/inspections
router.get('/inspections', (req, res) => {
  const companyId = req.companyId;
  const { since, limit, status, type } = req.query;

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
  if (type) {
    where += ' AND inspection_type = ?';
    params.push(type);
  }
  if (since) {
    where += ' AND inspected_at >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, inspection_no as inspectionNo,
              work_order_id as workOrderId, item_id as itemId, process_id as processId,
              equipment_id as equipmentId, inspection_type as inspectionType,
              status, inspected_at as inspectedAt, inspector_name as inspectorName,
              note, created_at as createdAt
       FROM quality_inspections
       WHERE ${where}
       ORDER BY inspected_at DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

// POST /api/v1/quality/inspections/:id/defects
router.post('/inspections/:id/defects', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const inspectionId = toId(req.params.id);
  const defectTypeId = toId(req.body?.defectTypeId);
  const qty = Number(req.body?.qty);
  const note = req.body?.note;

  if (!inspectionId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_defects',
      payload: { inspectionId: req.params.id, reason: 'INSPECTION_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  if (!defectTypeId || !Number.isFinite(qty) || qty <= 0) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_defects',
      payload: { inspectionId, defectTypeId, qty, reason: 'QTY_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_DEFECT_QTY_INVALID.code, ERR.QUALITY_DEFECT_QTY_INVALID.message));
  }

  const inspection = getInspection(inspectionId);
  if (!inspection || inspection.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_defects',
      payload: { inspectionId, reason: 'INSPECTION_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  const defectType = getDefectType(defectTypeId);
  if (!defectType || defectType.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_defects',
      payload: { inspectionId, defectTypeId, reason: 'DEFECT_TYPE_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_DEFECT_TYPE_NOT_FOUND.code, ERR.QUALITY_DEFECT_TYPE_NOT_FOUND.message));
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO quality_inspection_defects
         (company_id, inspection_id, defect_type_id, qty, note)
         VALUES (@companyId, @inspectionId, @defectTypeId, @qty, @note)`
      )
      .run({
        companyId,
        inspectionId,
        defectTypeId,
        qty,
        note: note || null,
      });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, inspection_id as inspectionId,
                defect_type_id as defectTypeId, qty, note, created_at as createdAt
         FROM quality_inspection_defects WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'quality_inspection_defects',
      entityId: result.lastInsertRowid,
      payload: { inspectionId, defectTypeId, qty },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspection_defects',
        payload: { inspectionId, defectTypeId, qty, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.QUALITY_DEFECT_DUPLICATE.code, ERR.QUALITY_DEFECT_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/quality/inspections/:id/defects
router.get('/inspections/:id/defects', (req, res) => {
  const companyId = req.companyId;
  const inspectionId = toId(req.params.id);

  if (!inspectionId) {
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  const inspection = getInspection(inspectionId);
  if (!inspection || inspection.company_id !== companyId) {
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, inspection_id as inspectionId,
              defect_type_id as defectTypeId, qty, note, created_at as createdAt
       FROM quality_inspection_defects
       WHERE company_id = ? AND inspection_id = ?
       ORDER BY id DESC`
    )
    .all(companyId, inspectionId);

  return res.json(ok(rows));
});

module.exports = router;
