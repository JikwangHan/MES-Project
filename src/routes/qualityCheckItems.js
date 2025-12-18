const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const VALID_TYPES = new Set(['NUMBER', 'TEXT', 'BOOL']);

const toNumberOrNull = (value) => {
  if (value === undefined || value === null || value === '') return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return null;
  return parsed;
};

const toRequiredFlag = (value) => {
  if (value === 0 || value === '0' || value === false || value === 'false') return 0;
  return 1;
};

// POST /api/v1/quality/check-items
router.post('/check-items', ensureNotViewer, (req, res) => {
  const { name, code, dataType, unit, lowerLimit, upperLimit, targetValue, isRequired } =
    req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code || !dataType) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_check_items',
      payload: { name, code, dataType, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'name, code, dataType는 필수입니다.'));
  }

  const typeValue = String(dataType).toUpperCase();
  if (!VALID_TYPES.has(typeValue)) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'quality_check_items',
      payload: { name, code, dataType: typeValue, reason: 'TYPE_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.QUALITY_CHECK_ITEM_TYPE_INVALID.code, ERR.QUALITY_CHECK_ITEM_TYPE_INVALID.message));
  }

  const lower = toNumberOrNull(lowerLimit);
  const upper = toNumberOrNull(upperLimit);
  const target = toNumberOrNull(targetValue);

  if (typeValue === 'NUMBER' && (lowerLimit !== undefined || upperLimit !== undefined || targetValue !== undefined)) {
    if ((lowerLimit !== undefined && lower === null) || (upperLimit !== undefined && upper === null) || (targetValue !== undefined && target === null)) {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_check_items',
        payload: { code, reason: 'LIMIT_INVALID' },
      });
      return res
        .status(400)
        .json(fail(ERR.QUALITY_RESULT_VALUE_INVALID.code, ERR.QUALITY_RESULT_VALUE_INVALID.message));
    }
  }

  try {
    const result = db
      .prepare(
        `INSERT INTO quality_check_items
         (company_id, name, code, data_type, unit, lower_limit, upper_limit, target_value, is_required)
         VALUES (@companyId, @name, @code, @dataType, @unit, @lowerLimit, @upperLimit, @targetValue, @isRequired)`
      )
      .run({
        companyId,
        name,
        code,
        dataType: typeValue,
        unit: unit || null,
        lowerLimit: lower,
        upperLimit: upper,
        targetValue: target,
        isRequired: toRequiredFlag(isRequired),
      });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, name, code,
                data_type as dataType, unit,
                lower_limit as lowerLimit, upper_limit as upperLimit,
                target_value as targetValue, is_required as isRequired,
                created_at as createdAt
         FROM quality_check_items WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'quality_check_items',
      entityId: result.lastInsertRowid,
      payload: { code, dataType: typeValue },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'quality_check_items',
        payload: { code, reason: 'DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.QUALITY_CHECK_ITEM_CODE_DUPLICATE.code, ERR.QUALITY_CHECK_ITEM_CODE_DUPLICATE.message));
    }
    console.error(err);
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/quality/check-items
router.get('/check-items', (req, res) => {
  const companyId = req.companyId;
  const { limit, dataType } = req.query;

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
  if (dataType) {
    where += ' AND data_type = ?';
    params.push(String(dataType).toUpperCase());
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code,
              data_type as dataType, unit,
              lower_limit as lowerLimit, upper_limit as upperLimit,
              target_value as targetValue, is_required as isRequired,
              created_at as createdAt
       FROM quality_check_items
       WHERE ${where}
       ORDER BY id DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

module.exports = router;
