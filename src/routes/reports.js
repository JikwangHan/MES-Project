const express = require('express');
const { db } = require('../db');
const { ok, fail } = require('../utils/response');
const ERR = require('../constants/errors');

const router = express.Router();

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_RANGE_DAYS = 366;

const toDateOnly = (str) => new Date(`${str}T00:00:00Z`);

const formatDate = (date) => date.toISOString().slice(0, 10);

const addDays = (date, days) => new Date(date.getTime() + days * 86400000);

const isValidDateString = (value) => {
  if (!DATE_RE.test(value)) return false;
  const parsed = toDateOnly(value);
  if (Number.isNaN(parsed.getTime())) return false;
  return formatDate(parsed) === value;
};

const parseDateRange = (query) => {
  const today = new Date();
  let from = query.from;
  let to = query.to;

  if (!from && !to) {
    to = formatDate(today);
    from = formatDate(addDays(today, -6));
  }

  if ((from && !isValidDateString(from)) || (to && !isValidDateString(to))) {
    return { ok: false, status: 400, err: ERR.REPORT_DATE_INVALID };
  }

  const fromDate = toDateOnly(from);
  const toDate = toDateOnly(to);
  const diffDays = Math.floor((toDate - fromDate) / 86400000);

  if (diffDays < 0) {
    return { ok: false, status: 400, err: ERR.REPORT_RANGE_INVALID };
  }

  if (diffDays > MAX_RANGE_DAYS) {
    return { ok: false, status: 400, err: ERR.REPORT_RANGE_TOO_LARGE };
  }

  return { ok: true, from, to, fromDate, toDate };
};

const buildDateList = (fromDate, toDate) => {
  const days = [];
  for (let d = fromDate; d <= toDate; d = addDays(d, 1)) {
    days.push(formatDate(d));
  }
  return days;
};

const toCountMap = (rows, keyField, valueField = 'cnt') => {
  const map = new Map();
  for (const row of rows) {
    map.set(row[keyField], row[valueField]);
  }
  return map;
};

const cacheGetStmt = db.prepare(
  `SELECT payload_json
   FROM report_kpi_cache
   WHERE company_id = ?
     AND report_name = ?
     AND from_date = ?
     AND to_date = ?
     AND params_json = ?
     AND CAST(expires_at AS INTEGER) > ?
   LIMIT 1`
);

const cacheUpsertStmt = db.prepare(
  `INSERT INTO report_kpi_cache (
     company_id,
     report_name,
     from_date,
     to_date,
     params_json,
     payload_json,
     expires_at,
     created_at
   ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
   ON CONFLICT(company_id, report_name, from_date, to_date, params_json)
   DO UPDATE SET
     payload_json = excluded.payload_json,
     expires_at = excluded.expires_at,
     created_at = excluded.created_at`
);

const getCacheMode = () => (process.env.REPORT_KPI_CACHE_MODE || 'PREFER').toUpperCase();

const getCacheTtlSeconds = () => {
  const raw = process.env.REPORT_KPI_CACHE_TTL_SECONDS;
  const ttl = raw ? Number(raw) : 120;
  if (!Number.isFinite(ttl) || ttl <= 0) return 120;
  return Math.floor(ttl);
};

const setReportCacheHeader = (res, cacheHit) => {
  if (cacheHit === true) {
    res.set('X-Report-Cache', 'HIT');
  } else if (cacheHit === false) {
    res.set('X-Report-Cache', 'MISS');
  }
};

const toStableJson = (value) => {
  if (value === null || value === undefined) return 'null';
  if (Array.isArray(value)) {
    return `[${value.map(toStableJson).join(',')}]`;
  }
  if (typeof value === 'object') {
    const keys = Object.keys(value).sort();
    const entries = keys.map((k) => `${JSON.stringify(k)}:${toStableJson(value[k])}`);
    return `{${entries.join(',')}}`;
  }
  return JSON.stringify(value);
};

const getCachedPayload = (companyId, reportName, from, to, paramsJson) => {
  const nowEpoch = Math.floor(Date.now() / 1000);
  const row = cacheGetStmt.get(companyId, reportName, from, to, paramsJson, nowEpoch);
  if (!row) return null;
  try {
    return JSON.parse(row.payload_json);
  } catch (err) {
    return null;
  }
};

const setCachedPayload = (companyId, reportName, from, to, paramsJson, payload) => {
  const ttl = getCacheTtlSeconds();
  const nowEpoch = Math.floor(Date.now() / 1000);
  const expiresAt = nowEpoch + ttl;
  const createdAt = new Date().toISOString();
  cacheUpsertStmt.run(
    companyId,
    reportName,
    from,
    to,
    paramsJson,
    JSON.stringify(payload),
    String(expiresAt),
    createdAt
  );
};

const withDbCache = (companyId, reportName, from, to, params, res, computeFn) => {
  const mode = getCacheMode();
  const paramsJson = toStableJson(params || {});

  if (mode !== 'OFF') {
    const cached = getCachedPayload(companyId, reportName, from, to, paramsJson);
    if (cached) {
      setReportCacheHeader(res, true);
      return { ok: true, data: cached };
    }

    if (mode === 'ENFORCE') {
      return { ok: false, status: 409, err: ERR.REPORT_KPI_CACHE_MISS };
    }
  }

  const data = computeFn();
  if (mode !== 'OFF') {
    setCachedPayload(companyId, reportName, from, to, paramsJson, data);
    setReportCacheHeader(res, false);
  }

  return { ok: true, data };
};

router.get('/summary', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query);
  if (!range.ok) return res.status(range.status).json(fail(range.err.code, range.err.message));

  const { from, to } = range;

  const result = withDbCache(companyId, 'summary', from, to, {}, res, () => {
    const workOrders = db
      .prepare(
        `SELECT COUNT(1) AS cnt
         FROM work_orders
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    const inspections = db
      .prepare(
        `SELECT COUNT(1) AS cnt
         FROM quality_inspections
         WHERE company_id = ?
           AND date(inspected_at) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    const results = db
      .prepare(
        `SELECT
           COALESCE(SUM(good_qty), 0) AS goodQty,
           COALESCE(SUM(defect_qty), 0) AS defectQty
         FROM production_results
         WHERE company_id = ?
           AND date(event_ts) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    const defects = db
      .prepare(
        `SELECT COALESCE(SUM(qty), 0) AS qty
         FROM quality_inspection_defects
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    const lots = db
      .prepare(
        `SELECT COUNT(1) AS cnt
         FROM lots
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    const telemetry = db
      .prepare(
        `SELECT COUNT(1) AS cnt
         FROM telemetry_events
         WHERE company_id = ?
           AND date(event_ts) BETWEEN ? AND ?`
      )
      .get(companyId, from, to);

    return {
      from,
      to,
      workOrdersTotal: workOrders.cnt || 0,
      inspectionsTotal: inspections.cnt || 0,
      productionGoodQty: results.goodQty || 0,
      productionDefectQty: results.defectQty || 0,
      inspectionDefectsTotal: defects.qty || 0,
      lotsCreated: lots.cnt || 0,
      telemetryEvents: telemetry.cnt || 0,
    };
  });

  if (!result.ok) {
    return res.status(result.status).json(fail(result.err.code, result.err.message));
  }
  return res.json(ok(result.data));
});

router.get('/daily', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query);
  if (!range.ok) return res.status(range.status).json(fail(range.err.code, range.err.message));

  const { from, to, fromDate, toDate } = range;
  const days = buildDateList(fromDate, toDate);

  const result = withDbCache(companyId, 'daily', from, to, {}, res, () => {
    const workOrdersRows = db
      .prepare(
        `SELECT date(created_at) AS day, COUNT(1) AS cnt
         FROM work_orders
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, from, to);

    const inspectionsRows = db
      .prepare(
        `SELECT date(inspected_at) AS day, COUNT(1) AS cnt
         FROM quality_inspections
         WHERE company_id = ?
           AND date(inspected_at) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, from, to);

    const defectsRows = db
      .prepare(
        `SELECT date(created_at) AS day, COALESCE(SUM(qty), 0) AS cnt
         FROM quality_inspection_defects
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, from, to);

    const lotsRows = db
      .prepare(
        `SELECT date(created_at) AS day, COUNT(1) AS cnt
         FROM lots
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, from, to);

    const telemetryRows = db
      .prepare(
        `SELECT date(event_ts) AS day, COUNT(1) AS cnt
         FROM telemetry_events
         WHERE company_id = ?
           AND date(event_ts) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, from, to);

    const workOrdersMap = toCountMap(workOrdersRows, 'day');
    const inspectionsMap = toCountMap(inspectionsRows, 'day');
    const defectsMap = toCountMap(defectsRows, 'day');
    const lotsMap = toCountMap(lotsRows, 'day');
    const telemetryMap = toCountMap(telemetryRows, 'day');

    const data = days.map((day) => ({
      date: day,
      workOrdersCount: workOrdersMap.get(day) || 0,
      inspectionsCount: inspectionsMap.get(day) || 0,
      defectsCount: defectsMap.get(day) || 0,
      lotsCount: lotsMap.get(day) || 0,
      telemetryCount: telemetryMap.get(day) || 0,
    }));

    return { from, to, items: data };
  });

  if (!result.ok) {
    return res.status(result.status).json(fail(result.err.code, result.err.message));
  }
  return res.json(ok(result.data));
});

router.get('/top-defects', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query);
  if (!range.ok) return res.status(range.status).json(fail(range.err.code, range.err.message));

  const limitRaw = req.query.limit;
  const limit = limitRaw ? Number(limitRaw) : 10;
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) {
    return res.status(400).json(fail(ERR.REPORT_LIMIT_INVALID.code, ERR.REPORT_LIMIT_INVALID.message));
  }

  const { from, to } = range;

  const result = withDbCache(
    companyId,
    'top-defects',
    from,
    to,
    { limit },
    res,
    () => {
    const rows = db
      .prepare(
        `SELECT
           dt.id,
           dt.code,
           dt.name,
           COALESCE(SUM(qid.qty), 0) AS qty
         FROM quality_inspection_defects qid
         JOIN defect_types dt ON qid.defect_type_id = dt.id
         WHERE qid.company_id = ?
           AND date(qid.created_at) BETWEEN ? AND ?
         GROUP BY dt.id
         ORDER BY qty DESC
         LIMIT ?`
      )
      .all(companyId, from, to, limit);

    return { from, to, items: rows };
    }
  );

  if (!result.ok) {
    return res.status(result.status).json(fail(result.err.code, result.err.message));
  }
  return res.json(ok(result.data));
});

module.exports = router;
