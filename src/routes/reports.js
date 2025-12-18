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

const parseDateRange = (query) => {
  const today = new Date();
  let from = query.from;
  let to = query.to;

  if (!from && !to) {
    to = formatDate(today);
    from = formatDate(addDays(today, -6));
  }

  if ((from && !DATE_RE.test(from)) || (to && !DATE_RE.test(to))) {
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

router.get('/summary', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query);
  if (!range.ok) return res.status(range.status).json(fail(range.err.code, range.err.message));

  const { from, to } = range;

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

  return res.json(
    ok({
      from,
      to,
      workOrdersTotal: workOrders.cnt || 0,
      inspectionsTotal: inspections.cnt || 0,
      productionGoodQty: results.goodQty || 0,
      productionDefectQty: results.defectQty || 0,
      inspectionDefectsTotal: defects.qty || 0,
      lotsCreated: lots.cnt || 0,
      telemetryEvents: telemetry.cnt || 0,
    })
  );
});

router.get('/daily', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query);
  if (!range.ok) return res.status(range.status).json(fail(range.err.code, range.err.message));

  const { from, to, fromDate, toDate } = range;
  const days = buildDateList(fromDate, toDate);

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

  return res.json(ok({ from, to, items: data }));
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

  return res.json(ok({ from, to, items: rows }));
});

module.exports = router;
