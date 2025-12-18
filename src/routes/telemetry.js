const express = require('express');
const { db, insertAuditLog, getEquipmentByDeviceKey } = require('../db');
const { ok, fail } = require('../utils/response');
const ERR = require('../constants/errors');
const {
  decryptSecret,
  sha256Hex,
  hmacSha256Hex,
  timingSafeEqualHex,
} = require('../utils/crypto');
const { stableStringify } = require('../utils/canonicalJson');

const router = express.Router();

const DEBUG = process.env.DEBUG_TELEMETRY_AUTH === '1';

const nonceExists = (companyId, equipmentId, nonce) =>
  !!db
    .prepare(
      'SELECT 1 FROM telemetry_nonces WHERE company_id = ? AND equipment_id = ? AND nonce = ?'
    )
    .get(companyId, equipmentId, nonce);

const insertNonce = (companyId, equipmentId, nonce, ts) => {
  db.prepare(
    `INSERT INTO telemetry_nonces (company_id, equipment_id, nonce, ts, created_at)
     VALUES (@companyId, @equipmentId, @nonce, @ts, @createdAt)`
  ).run({
    companyId,
    equipmentId,
    nonce,
    ts,
    createdAt: new Date().toISOString(),
  });
};

const getHeader = (req, name) => {
  const v = req.headers[String(name).toLowerCase()];
  return typeof v === 'string' ? v.trim() : v;
};

const getCanonicalBody = (req) => {
  const canonicalHeader = String(getHeader(req, 'x-canonical') || '').toLowerCase();
  if (canonicalHeader === 'legacy-json') {
    return JSON.stringify(req.body || {});
  }
  // 기본값: stable-json
  return stableStringify(req.body || {});
};

const parseAuthHeaders = (req) => {
  const deviceKeyId = getHeader(req, 'x-device-key');
  const tsHeader = getHeader(req, 'x-ts');
  const nonce = getHeader(req, 'x-nonce');
  const signature = getHeader(req, 'x-signature');

  if (!deviceKeyId || !tsHeader || !nonce || !signature) {
    return { ok: false, status: 401, err: ERR.TELEMETRY_AUTH_REQUIRED };
  }

  const tsNum = Number(tsHeader);
  if (!Number.isInteger(tsNum)) {
    return { ok: false, status: 401, err: ERR.TELEMETRY_TS_INVALID };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - tsNum) > 300) {
    return { ok: false, status: 401, err: ERR.TELEMETRY_TS_EXPIRED };
  }

  return { ok: true, deviceKeyId, tsNum, nonce, signature };
};

const requireEquipmentCodeMatch = (equipmentCode, equipmentAuth) => {
  if (!equipmentCode) {
    return { ok: false, status: 400, err: ERR.TELEMETRY_EQUIPMENT_CODE_REQUIRED };
  }
  if (!equipmentAuth || equipmentCode !== equipmentAuth.code) {
    return { ok: false, status: 400, err: ERR.TELEMETRY_EQUIPMENT_NOT_FOUND };
  }
  return { ok: true };
};

const verifySignatureOrFail = ({
  companyId,
  deviceKeyId,
  tsNum,
  nonce,
  signature,
  rawBody,
  equipmentAuth,
}) => {
  let secret;
  try {
    secret = decryptSecret(equipmentAuth.device_key_secret_enc);
  } catch (e) {
    return { ok: false, status: 500, err: ERR.SERVER_ERROR };
  }

  const bodyHash = sha256Hex(rawBody);
  const canonical = `${companyId}\n${deviceKeyId}\n${tsNum}\n${nonce}\n${bodyHash}`;
  const sigCalc = hmacSha256Hex(secret, canonical);
  if (!timingSafeEqualHex(sigCalc, signature)) {
    if (DEBUG) {
      console.error('[telemetry-auth][sig-mismatch]', {
        canonical,
        sigCalc: String(sigCalc).slice(0, 12) + '...',
        signature: String(signature).slice(0, 12) + '...',
      });
    }
    return { ok: false, status: 401, err: ERR.TELEMETRY_SIGNATURE_INVALID };
  }
  return { ok: true };
};

const verifyNonceOrFail = (companyId, equipmentId, nonce) => {
  if (nonceExists(companyId, equipmentId, nonce)) {
    return { ok: false, status: 401, err: ERR.TELEMETRY_NONCE_REPLAY };
  }
  return { ok: true };
};

// POST /api/v1/telemetry/events
router.post('/events', (req, res) => {
  try {
    const { equipmentCode, timestamp, eventType, payload } = req.body || {};
    const companyId = req.companyId;
    const role = req.userRole; // VIEWER도 허용 (장비/게이트웨이 역할 가정)

    const auth = parseAuthHeaders(req);
    if (!auth.ok) {
      return res.status(auth.status).json(fail(auth.err.code, auth.err.message));
    }

    const equipmentAuth = getEquipmentByDeviceKey(companyId, auth.deviceKeyId);
    if (!equipmentAuth || !equipmentAuth.id) {
      return res
        .status(401)
        .json(
          fail(ERR.TELEMETRY_DEVICE_KEY_INVALID.code, ERR.TELEMETRY_DEVICE_KEY_INVALID.message)
        );
    }
    if (equipmentAuth.device_key_status !== 'ACTIVE') {
      return res
        .status(401)
        .json(
          fail(ERR.TELEMETRY_DEVICE_KEY_INVALID.code, ERR.TELEMETRY_DEVICE_KEY_INVALID.message)
        );
    }

    if (DEBUG) {
      console.log('[telemetry-auth]', {
        companyId,
        deviceKeyId: String(auth.deviceKeyId).slice(0, 6) + '***',
        equipmentCode,
        equipmentAuthFound: !!equipmentAuth,
        equipmentId: equipmentAuth?.id,
        equipmentAuthCode: equipmentAuth?.code,
        ts: auth.tsNum,
        nonce: String(auth.nonce).slice(0, 6) + '***',
      });
    }

    const codeCheck = requireEquipmentCodeMatch(equipmentCode, equipmentAuth);
    if (!codeCheck.ok) {
      return res.status(codeCheck.status).json(fail(codeCheck.err.code, codeCheck.err.message));
    }

    if (DEBUG) {
      console.log('[telemetry-auth][raw-body]', {
        hasRaw: !!req.rawBody,
        rawLength: req.rawBody?.length,
      });
      if (req.rawBody) {
        console.log('[telemetry-auth][raw-body-text]', req.rawBody.toString('utf8'));
      }
    }

    const canonicalHeader = String(getHeader(req, 'x-canonical') || '').toLowerCase();
    const canonicalBody = getCanonicalBody(req);
    if (DEBUG && canonicalHeader === 'stable-json') {
      console.log('[telemetry-auth][stable-json]', {
        bodyHash: sha256Hex(canonicalBody),
        canonical: canonicalBody,
      });
    }

    const sigCheck = verifySignatureOrFail({
      companyId,
      deviceKeyId: auth.deviceKeyId,
      tsNum: auth.tsNum,
      nonce: auth.nonce,
      signature: auth.signature,
      rawBody: canonicalBody,
      equipmentAuth,
    });
    if (!sigCheck.ok) {
      if (DEBUG) {
        console.error('[telemetry-auth][sig-fail]', sigCheck);
      }
      const errInfo = sigCheck.err || ERR.SERVER_ERROR;
      return res.status(sigCheck.status).json(fail(errInfo.code, errInfo.message));
    }

    const nonceCheck = verifyNonceOrFail(companyId, equipmentAuth.id, auth.nonce);
    if (!nonceCheck.ok) {
      return res.status(nonceCheck.status).json(fail(nonceCheck.err.code, nonceCheck.err.message));
    }

    insertNonce(companyId, equipmentAuth.id, auth.nonce, auth.tsNum);

    const eventTs = timestamp || new Date().toISOString();
    let payloadJson = '{}';
    if (payload !== undefined && payload !== null) {
      if (typeof payload === 'string') {
        payloadJson = payload;
      } else {
        try {
          payloadJson = JSON.stringify(payload);
        } catch (e) {
          return res
            .status(400)
            .json(fail(ERR.VALIDATION_ERROR.code, 'payload를 JSON으로 직렬화할 수 없습니다.'));
        }
      }
    }

    const eventTypeValue = eventType || 'TELEMETRY';
    const now = new Date().toISOString();

    const stmt = db.prepare(`
      INSERT INTO telemetry_events (
        company_id, equipment_id, equipment_code, event_type, event_ts, payload_json, received_at
      )
      VALUES (@companyId, @equipmentId, @equipmentCode, @eventType, @eventTs, @payloadJson, @receivedAt)
    `);
    const result = stmt.run({
      companyId,
      equipmentId: equipmentAuth.id,
      equipmentCode,
      eventType: eventTypeValue,
      eventTs,
      payloadJson,
      receivedAt: now,
    });

    db.prepare(
      `UPDATE equipments SET device_key_last_seen_at = @now WHERE id = @id`
    ).run({ now, id: equipmentAuth.id });

    const created = db
      .prepare(
        `SELECT id, company_id as companyId, equipment_id as equipmentId, equipment_code as equipmentCode,
                event_type as eventType, event_ts as eventTs, payload_json as payloadJson, received_at as receivedAt
         FROM telemetry_events WHERE id = ?`
      )
      .get(result.lastInsertRowid);

    insertAuditLog({
      companyId,
      actorRole: role,
      action: 'CREATE',
      entity: 'telemetry_events',
      entityId: result.lastInsertRowid,
      payload: { equipmentCode, eventType: eventTypeValue },
    });

    return res.status(201).json(ok(created));
  } catch (err) {
    console.error('telemetry server error', err);
    return res
      .status(500)
      .json(fail(ERR.SERVER_ERROR.code, ERR.SERVER_ERROR.message));
  }
});

// GET /api/v1/telemetry/events?since=&limit=
router.get('/events', (req, res) => {
  const companyId = req.companyId;
  const { since, limit } = req.query;

  let limitValue = 50;
  if (limit !== undefined) {
    const parsed = Number(limit);
    if (!Number.isInteger(parsed) || parsed <= 0 || parsed > 200) {
      return res
        .status(400)
        .json(fail(ERR.TELEMETRY_LIMIT_INVALID.code, ERR.TELEMETRY_LIMIT_INVALID.message));
    }
    limitValue = parsed;
  }

  const params = [companyId];
  let sinceClause = '';
  if (since) {
    sinceClause = 'AND event_ts >= ?';
    params.push(since);
  }

  const rows = db
    .prepare(
      `SELECT id, company_id as companyId, equipment_id as equipmentId, equipment_code as equipmentCode,
              event_type as eventType, event_ts as eventTs, payload_json as payloadJson, received_at as receivedAt
       FROM telemetry_events
       WHERE company_id = ?
       ${sinceClause}
       ORDER BY event_ts DESC
       LIMIT ?`
    )
    .all(...params, limitValue);

  return res.json(ok(rows));
});

module.exports = router;
