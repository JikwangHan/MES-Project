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

const getInspection = (id) =>
  db
    .prepare('SELECT id, company_id, status FROM quality_inspections WHERE id = ?')
    .get(id);

const getCheckItemById = (id) =>
  db
    .prepare(
      `SELECT id, company_id, data_type, lower_limit, upper_limit, target_value
       FROM quality_check_items WHERE id = ?`
    )
    .get(id);

const getCheckItemByCode = (companyId, code) =>
  db
    .prepare(
      `SELECT id, company_id, data_type, lower_limit, upper_limit, target_value
       FROM quality_check_items WHERE company_id = ? AND code = ?`
    )
    .get(companyId, code);

const toBoolFlag = (value) => {
  if (value === true || value === 'true' || value === 1 || value === '1') return 1;
  if (value === false || value === 'false' || value === 0 || value === '0') return 0;
  return null;
};

// POST /api/v1/quality/inspections/:id/results
router.post('/inspections/:id/results', ensureNotViewer, (req, res) => {
  const companyId = req.companyId;
  const role = req.userRole;
  const inspectionId = toId(req.params.id);
  const { checkItemId, checkItemCode, measuredValue, measuredValueText, measuredValueBool, note } =
    req.body || {};

  if (!inspectionId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_results',
      payload: { inspectionId: req.params.id, reason: 'INSPECTION_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  const inspection = getInspection(inspectionId);
  if (!inspection || inspection.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_results',
      payload: { inspectionId, reason: 'INSPECTION_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_INSPECTION_NOT_FOUND.code, ERR.QUALITY_INSPECTION_NOT_FOUND.message));
  }

  const checkItemIdValue = toId(checkItemId);
  let checkItem = null;
  if (checkItemIdValue) {
    checkItem = getCheckItemById(checkItemIdValue);
  } else if (checkItemCode) {
    checkItem = getCheckItemByCode(companyId, checkItemCode);
  }

  if (!checkItem || checkItem.company_id !== companyId) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_inspection_results',
      payload: { inspectionId, checkItemId, checkItemCode, reason: 'CHECK_ITEM_NOT_FOUND' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_CHECK_ITEM_NOT_FOUND.code, ERR.QUALITY_CHECK_ITEM_NOT_FOUND.message));
  }

  const dataType = checkItem.data_type;
  let valueNum = null;
  let valueText = null;
  let valueBool = null;
  let judgement = 'NA';

  if (dataType === 'NUMBER') {
    const num = Number(measuredValue ?? measuredValueText);
    if (!Number.isFinite(num)) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspection_results',
        payload: { inspectionId, checkItemId: checkItem.id, reason: 'VALUE_INVALID' },
      });
      return res
        .status(400)
        .json(fail(ERR.QUALITY_RESULT_VALUE_INVALID.code, ERR.QUALITY_RESULT_VALUE_INVALID.message));
    }
    valueNum = num;
    judgement = 'PASS';
    if (checkItem.lower_limit !== null && num < Number(checkItem.lower_limit)) {
      judgement = 'FAIL';
    }
    if (checkItem.upper_limit !== null && num > Number(checkItem.upper_limit)) {
      judgement = 'FAIL';
    }
  } else if (dataType === 'TEXT') {
    const text = measuredValueText ?? measuredValue;
    if (typeof text !== 'string' || text.trim() === '') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspection_results',
        payload: { inspectionId, checkItemId: checkItem.id, reason: 'VALUE_INVALID' },
      });
      return res
        .status(400)
        .json(fail(ERR.QUALITY_RESULT_VALUE_INVALID.code, ERR.QUALITY_RESULT_VALUE_INVALID.message));
    }
    valueText = text;
  } else if (dataType === 'BOOL') {
    const boolVal = toBoolFlag(measuredValueBool ?? measuredValue);
    if (boolVal === null) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspection_results',
        payload: { inspectionId, checkItemId: checkItem.id, reason: 'VALUE_INVALID' },
      });
      return res
        .status(400)
        .json(fail(ERR.QUALITY_RESULT_VALUE_INVALID.code, ERR.QUALITY_RESULT_VALUE_INVALID.message));
    }
    valueBool = boolVal;
  } else {
    return res
      .status(400)
      .json(fail(ERR.QUALITY_CHECK_ITEM_TYPE_INVALID.code, ERR.QUALITY_CHECK_ITEM_TYPE_INVALID.message));
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO quality_inspection_results
         (company_id, inspection_id, check_item_id, measured_value_num, measured_value_text, measured_value_bool, judgement, note)
         VALUES (@companyId, @inspectionId, @checkItemId, @valueNum, @valueText, @valueBool, @judgement, @note)`
      )
      .run({
        companyId,
        inspectionId,
        checkItemId: checkItem.id,
        valueNum,
        valueText,
        valueBool,
        judgement,
        note: note || null,
      });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, inspection_id as inspectionId,
                check_item_id as checkItemId, measured_value_num as measuredValueNum,
                measured_value_text as measuredValueText, measured_value_bool as measuredValueBool,
                judgement, note, created_at as createdAt
         FROM quality_inspection_results WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    if (judgement === 'FAIL' && inspection.status !== 'FAIL') {
      db.prepare('UPDATE quality_inspections SET status = ? WHERE id = ?').run('FAIL', inspectionId);
    }

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'quality_inspection_results',
      entityId: result.lastInsertRowid,
      payload: { inspectionId, checkItemId: checkItem.id, judgement },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_inspection_results',
        payload: { inspectionId, checkItemId: checkItem.id, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.QUALITY_RESULT_DUPLICATE.code, ERR.QUALITY_RESULT_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/quality/inspections/:id/results
router.get('/inspections/:id/results', (req, res) => {
  const companyId = req.companyId;
  const inspectionId = toId(req.params.id);
  const { since, limit } = req.query;

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

  const params = [companyId, inspectionId];
  let sinceClause = '';
  if (since) {
    sinceClause = 'AND created_at >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, inspection_id as inspectionId,
              check_item_id as checkItemId, measured_value_num as measuredValueNum,
              measured_value_text as measuredValueText, measured_value_bool as measuredValueBool,
              judgement, note, created_at as createdAt
       FROM quality_inspection_results
       WHERE company_id = ? AND inspection_id = ?
       ${sinceClause}
       ORDER BY id DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

module.exports = router;
