const express = require('express');
const { db } = require('../db');
const { ok, fail } = require('../utils/response');
const ERR = require('../constants/errors');

const router = express.Router();

const addDays = (date, days) => new Date(date.getTime() + days * 86400000);
const toDateOnly = (date) => new Date(date.toISOString().slice(0, 10));
const formatDate = (date) => date.toISOString().slice(0, 10);

const buildDateList = (fromDate, toDate) => {
  const days = [];
  for (let d = fromDate; d <= toDate; d = addDays(d, 1)) {
    days.push(formatDate(d));
  }
  return days;
};

const toCountMap = (rows, keyField) => {
  const map = new Map();
  for (const row of rows) {
    map.set(row[keyField], row.cnt);
  }
  return map;
};

const parseDays = (raw, defaultDays, maxDays) => {
  if (raw === undefined || raw === null || raw === '') return defaultDays;
  const days = Number(raw);
  if (!Number.isInteger(days) || days < 1 || days > maxDays) return null;
  return days;
};

const parseLimit = (raw, defaultLimit, maxLimit) => {
  if (raw === undefined || raw === null || raw === '') return defaultLimit;
  const limit = Number(raw);
  if (!Number.isInteger(limit) || limit < 1 || limit > maxLimit) return null;
  return limit;
};

router.get('/overview', (req, res) => {
  const companyId = req.companyId;
  const days = parseDays(req.query.days, 7, 90);
  if (!days) {
    return res.status(400).json(fail(ERR.DASHBOARD_DAYS_INVALID.code, ERR.DASHBOARD_DAYS_INVALID.message));
  }

  const toDate = toDateOnly(new Date());
  const fromDate = addDays(toDate, -(days - 1));
  const from = formatDate(fromDate);
  const to = formatDate(toDate);

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

  const defects = db
    .prepare(
      `SELECT COALESCE(SUM(qty), 0) AS cnt
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

  const recentLots = db
    .prepare(
      `SELECT lot_no AS lotNo, item_id AS itemId, qty, unit, status, created_at AS createdAt
       FROM lots
       WHERE company_id = ?
       ORDER BY created_at DESC
       LIMIT 5`
    )
    .all(companyId);

  const recentInspections = db
    .prepare(
      `SELECT inspection_no AS inspectionNo, status, inspected_at AS inspectedAt
       FROM quality_inspections
       WHERE company_id = ?
       ORDER BY inspected_at DESC
       LIMIT 5`
    )
    .all(companyId);

  const recentWorkOrders = db
    .prepare(
      `SELECT wo_no AS woNo, status, created_at AS createdAt
       FROM work_orders
       WHERE company_id = ?
       ORDER BY created_at DESC
       LIMIT 5`
    )
    .all(companyId);

  const topDefects = db
    .prepare(
      `SELECT dt.code, dt.name, COALESCE(SUM(qid.qty), 0) AS qty
       FROM quality_inspection_defects qid
       JOIN defect_types dt ON qid.defect_type_id = dt.id
       WHERE qid.company_id = ?
         AND date(qid.created_at) BETWEEN ? AND ?
       GROUP BY dt.id
       ORDER BY qty DESC
       LIMIT 5`
    )
    .all(companyId, from, to);

  return res.json(
    ok({
      from,
      to,
      workOrdersTotal: workOrders.cnt || 0,
      inspectionsTotal: inspections.cnt || 0,
      defectsTotal: defects.cnt || 0,
      lotsCreated: lots.cnt || 0,
      recentLots,
      recentInspections,
      recentWorkOrders,
      topDefects,
    })
  );
});

router.get('/activity', (req, res) => {
  const companyId = req.companyId;
  const days = parseDays(req.query.days, 14, 90);
  if (!days) {
    return res.status(400).json(fail(ERR.DASHBOARD_DAYS_INVALID.code, ERR.DASHBOARD_DAYS_INVALID.message));
  }

  const toDate = toDateOnly(new Date());
  const fromDate = addDays(toDate, -(days - 1));
  const from = formatDate(fromDate);
  const to = formatDate(toDate);
  const dayList = buildDateList(fromDate, toDate);

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

  const workOrdersMap = toCountMap(workOrdersRows, 'day');
  const inspectionsMap = toCountMap(inspectionsRows, 'day');
  const defectsMap = toCountMap(defectsRows, 'day');
  const lotsMap = toCountMap(lotsRows, 'day');

  const items = dayList.map((day) => ({
    date: day,
    workOrdersCount: workOrdersMap.get(day) || 0,
    inspectionsCount: inspectionsMap.get(day) || 0,
    defectsCount: defectsMap.get(day) || 0,
    lotsCount: lotsMap.get(day) || 0,
  }));

  return res.json(ok({ from, to, items }));
});

router.get('/alerts', (req, res) => {
  const companyId = req.companyId;
  const limit = parseLimit(req.query.limit, 10, 50);
  if (!limit) {
    return res.status(400).json(fail(ERR.DASHBOARD_LIMIT_INVALID.code, ERR.DASHBOARD_LIMIT_INVALID.message));
  }

  const recentInspections = db
    .prepare(
      `SELECT inspection_no AS inspectionNo, status, inspected_at AS inspectedAt
       FROM quality_inspections
       WHERE company_id = ?
       ORDER BY inspected_at DESC
       LIMIT ?`
    )
    .all(companyId, limit);

  const recentWorkOrders = db
    .prepare(
      `SELECT wo_no AS woNo, status, created_at AS createdAt
       FROM work_orders
       WHERE company_id = ?
       ORDER BY created_at DESC
       LIMIT ?`
    )
    .all(companyId, limit);

  const recentDefects = db
    .prepare(
      `SELECT dt.code, dt.name, qid.qty, qid.created_at AS createdAt
       FROM quality_inspection_defects qid
       JOIN defect_types dt ON qid.defect_type_id = dt.id
       WHERE qid.company_id = ?
       ORDER BY qid.created_at DESC
       LIMIT ?`
    )
    .all(companyId, limit);

  return res.json(
    ok({
      recentInspections,
      recentWorkOrders,
      recentDefects,
    })
  );
});

module.exports = router;
