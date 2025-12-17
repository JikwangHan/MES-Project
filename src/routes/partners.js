const express = require('express');
const { db, insertAuditLog } = require('../db');
const { ok, fail } = require('../utils/response');
const { ensureNotViewer } = require('../middleware/auth');
const ERR = require('../constants/errors');

const router = express.Router();

const VALID_TYPES = ['CUSTOMER', 'VENDOR', 'BOTH'];

// POST /api/v1/partners
router.post('/', ensureNotViewer, (req, res) => {
  const { name, code, type, contactName, phone, email, address, isActive } = req.body || {};
  const companyId = req.companyId;
  const role = req.userRole;

  if (!name || !code || !type) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'partners',
      payload: { name, code, type, reason: 'VALIDATION' },
    });
    return res
      .status(400)
      .json(fail(ERR.VALIDATION_ERROR.code, 'name, code, type는 필수입니다.'));
  }

  if (!VALID_TYPES.includes(type)) {
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'partners',
      payload: { name, code, type, reason: 'TYPE_INVALID' },
    });
    return res
      .status(400)
      .json(fail(ERR.PARTNER_TYPE_INVALID.code, ERR.PARTNER_TYPE_INVALID.message));
  }

  const isActiveValue = typeof isActive === 'number' ? isActive : 1;

  try {
    const stmt = db.prepare(`
      INSERT INTO partners (company_id, name, code, type, contact_name, phone, email, address, is_active, created_by_role)
      VALUES (@companyId, @name, @code, @type, @contactName, @phone, @email, @address, @isActive, @role)
    `);
    const result = stmt.run({
      companyId,
      name,
      code,
      type,
      contactName: contactName || null,
      phone: phone || null,
      email: email || null,
      address: address || null,
      isActive: isActiveValue,
      role,
    });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, name, code, type, contact_name as contactName,
                phone, email, address, is_active as isActive, created_at as createdAt
         FROM partners WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'partners',
      entityId: result.lastInsertRowid,
      payload: { name, code, type },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    if (err.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      insertAuditLog({
        companyId,
        actorRole: role,
        action: 'CREATE_FAIL',
        entity: 'partners',
        payload: { name, code, type, reason: 'PARTNER_CODE_DUPLICATE' },
      });
      return res
        .status(409)
        .json(fail(ERR.PARTNER_CODE_DUPLICATE.code, ERR.PARTNER_CODE_DUPLICATE.message));
    }
    console.error(err);
    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE_FAIL',
      entity: 'partners',
      payload: { name, code, type, reason: 'SERVER_ERROR' },
    });
    return res.status(500).json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/partners
router.get('/', (req, res) => {
  const companyId = req.companyId;
  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, name, code, type, contact_name as contactName,
              phone, email, address, is_active as isActive, created_at as createdAt
       FROM partners
       WHERE company_id = ?
       ORDER BY id`
    )
    .all(companyId);
  return res.json(ok(rows));
});

module.exports = router;
