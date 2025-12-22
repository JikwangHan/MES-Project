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

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const parseDateOnly = (value) => {
  if (!DATE_RE.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;
  return toDateOnly(parsed);
};

const parseDateRange = (fromRaw, toRaw, defaultDays, maxDays) => {
  if (!fromRaw && !toRaw) {
    const toDate = toDateOnly(new Date());
    const fromDate = addDays(toDate, -(defaultDays - 1));
    return {
      fromDate,
      toDate,
      from: formatDate(fromDate),
      to: formatDate(toDate),
    };
  }

  if (!fromRaw || !toRaw) {
    return { error: ERR.DASHBOARD_RANGE_INVALID };
  }

  const fromDate = parseDateOnly(fromRaw);
  const toDate = parseDateOnly(toRaw);
  if (!fromDate || !toDate) {
    return { error: ERR.DASHBOARD_DATE_INVALID };
  }

  if (fromDate > toDate) {
    return { error: ERR.DASHBOARD_RANGE_INVALID };
  }

  const days = Math.floor((toDate - fromDate) / 86400000) + 1;
  if (days > maxDays) {
    return { error: ERR.DASHBOARD_RANGE_TOO_LARGE };
  }

  return {
    fromDate,
    toDate,
    from: formatDate(fromDate),
    to: formatDate(toDate),
  };
};

const parseThreshold = (raw, defaultValue) => {
  if (raw === undefined || raw === null || raw === '') return defaultValue;
  const value = Number(raw);
  if (Number.isNaN(value) || value < 0 || value > 1) return null;
  return value;
};

const calcDefectRatePct = (goodQty, defectQty) => {
  const total = goodQty + defectQty;
  if (!total) return 0;
  return Number(((defectQty / total) * 100).toFixed(2));
};

const getStaleMinutes = () => {
  const value = Number(process.env.TELEMETRY_STALE_MIN || 5);
  return Number.isFinite(value) && value > 0 ? value : 5;
};

router.get('/kpis', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query.from, req.query.to, 7, 366);
  if (range.error) {
    return res.status(400).json(fail(range.error.code, range.error.message));
  }

  const workOrders = db
    .prepare(
      `SELECT COUNT(1) AS cnt
       FROM work_orders
       WHERE company_id = ?
         AND date(created_at) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const production = db
    .prepare(
      `SELECT COALESCE(SUM(good_qty), 0) AS goodQty,
              COALESCE(SUM(defect_qty), 0) AS defectQty
       FROM production_results
       WHERE company_id = ?
         AND date(event_ts) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const inspections = db
    .prepare(
      `SELECT COUNT(1) AS cnt
       FROM quality_inspections
       WHERE company_id = ?
         AND date(inspected_at) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const inspectionDefects = db
    .prepare(
      `SELECT COALESCE(SUM(qty), 0) AS cnt
       FROM quality_inspection_defects
       WHERE company_id = ?
         AND date(created_at) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const lots = db
    .prepare(
      `SELECT COUNT(1) AS cnt
       FROM lots
       WHERE company_id = ?
         AND date(created_at) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const telemetry = db
    .prepare(
      `SELECT COUNT(1) AS cnt
       FROM telemetry_events
       WHERE company_id = ?
         AND date(event_ts) BETWEEN ? AND ?`
    )
    .get(companyId, range.from, range.to);

  const defectRatePct = calcDefectRatePct(production.goodQty || 0, production.defectQty || 0);

  return res.json(
    ok({
      from: range.from,
      to: range.to,
      workOrdersTotal: workOrders.cnt || 0,
      productionGoodQty: production.goodQty || 0,
      productionDefectQty: production.defectQty || 0,
      defectRatePct,
      inspectionsTotal: inspections.cnt || 0,
      inspectionDefectsTotal: inspectionDefects.cnt || 0,
      lotsCreated: lots.cnt || 0,
      telemetryEvents: telemetry.cnt || 0,
    })
  );
});

router.get('/trends/daily', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query.from, req.query.to, 14, 366);
  if (range.error) {
    return res.status(400).json(fail(range.error.code, range.error.message));
  }

  const dayList = buildDateList(range.fromDate, range.toDate);

  const productionRows = db
    .prepare(
      `SELECT date(event_ts) AS day,
              COALESCE(SUM(good_qty), 0) AS goodQty,
              COALESCE(SUM(defect_qty), 0) AS defectQty
       FROM production_results
       WHERE company_id = ?
         AND date(event_ts) BETWEEN ? AND ?
       GROUP BY day`
    )
    .all(companyId, range.from, range.to);

  const inspectionsRows = db
    .prepare(
      `SELECT date(inspected_at) AS day, COUNT(1) AS cnt
       FROM quality_inspections
       WHERE company_id = ?
         AND date(inspected_at) BETWEEN ? AND ?
       GROUP BY day`
    )
    .all(companyId, range.from, range.to);

  const defectsRows = db
    .prepare(
      `SELECT date(created_at) AS day, COALESCE(SUM(qty), 0) AS cnt
       FROM quality_inspection_defects
       WHERE company_id = ?
         AND date(created_at) BETWEEN ? AND ?
       GROUP BY day`
    )
    .all(companyId, range.from, range.to);

  const lotsRows = db
    .prepare(
      `SELECT date(created_at) AS day, COUNT(1) AS cnt
       FROM lots
       WHERE company_id = ?
         AND date(created_at) BETWEEN ? AND ?
       GROUP BY day`
    )
    .all(companyId, range.from, range.to);

  const telemetryRows = db
    .prepare(
      `SELECT date(event_ts) AS day, COUNT(1) AS cnt
       FROM telemetry_events
       WHERE company_id = ?
         AND date(event_ts) BETWEEN ? AND ?
       GROUP BY day`
    )
    .all(companyId, range.from, range.to);

  const productionMap = new Map();
  for (const row of productionRows) {
    productionMap.set(row.day, { goodQty: row.goodQty || 0, defectQty: row.defectQty || 0 });
  }
  const inspectionsMap = toCountMap(inspectionsRows, 'day');
  const defectsMap = toCountMap(defectsRows, 'day');
  const lotsMap = toCountMap(lotsRows, 'day');
  const telemetryMap = toCountMap(telemetryRows, 'day');

  const items = dayList.map((day) => {
    const production = productionMap.get(day) || { goodQty: 0, defectQty: 0 };
    const defectRatePct = calcDefectRatePct(production.goodQty, production.defectQty);
    return {
      date: day,
      productionGoodQty: production.goodQty,
      productionDefectQty: production.defectQty,
      defectRatePct,
      inspectionsTotal: inspectionsMap.get(day) || 0,
      inspectionDefectsTotal: defectsMap.get(day) || 0,
      lotsCreated: lotsMap.get(day) || 0,
      telemetryEvents: telemetryMap.get(day) || 0,
    };
  });

  return res.json(ok({ from: range.from, to: range.to, items }));
});

router.get('/top/defects', (req, res) => {
  const companyId = req.companyId;
  const range = parseDateRange(req.query.from, req.query.to, 7, 366);
  if (range.error) {
    return res.status(400).json(fail(range.error.code, range.error.message));
  }

  const limit = parseLimit(req.query.limit, 10, 20);
  if (!limit) {
    return res.status(400).json(fail(ERR.DASHBOARD_LIMIT_INVALID.code, ERR.DASHBOARD_LIMIT_INVALID.message));
  }

  const items = db
    .prepare(
      `SELECT dt.code, dt.name, COALESCE(SUM(qid.qty), 0) AS qty
       FROM quality_inspection_defects qid
       JOIN defect_types dt ON qid.defect_type_id = dt.id
       WHERE qid.company_id = ?
         AND date(qid.created_at) BETWEEN ? AND ?
       GROUP BY dt.id
       ORDER BY qty DESC
       LIMIT ?`
    )
    .all(companyId, range.from, range.to, limit);

  return res.json(ok({ from: range.from, to: range.to, items }));
});

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
  if (req.query.from || req.query.to || req.query.defectRateThreshold !== undefined) {
    const range = parseDateRange(req.query.from, req.query.to, 7, 366);
    if (range.error) {
      return res.status(400).json(fail(range.error.code, range.error.message));
    }

    const threshold = parseThreshold(req.query.defectRateThreshold, 0.05);
    if (threshold === null) {
      return res.status(400).json(fail(ERR.DASHBOARD_THRESHOLD_INVALID.code, ERR.DASHBOARD_THRESHOLD_INVALID.message));
    }

    const production = db
      .prepare(
        `SELECT COALESCE(SUM(good_qty), 0) AS goodQty,
                COALESCE(SUM(defect_qty), 0) AS defectQty
         FROM production_results
         WHERE company_id = ?
           AND date(event_ts) BETWEEN ? AND ?`
      )
      .get(companyId, range.from, range.to);

    const inspections = db
      .prepare(
        `SELECT COUNT(1) AS cnt
         FROM quality_inspections
         WHERE company_id = ?
           AND date(inspected_at) BETWEEN ? AND ?`
      )
      .get(companyId, range.from, range.to);

    const inspectionDefects = db
      .prepare(
        `SELECT COALESCE(SUM(qty), 0) AS cnt
         FROM quality_inspection_defects
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?`
      )
      .get(companyId, range.from, range.to);

    const defectsDailyRows = db
      .prepare(
        `SELECT date(created_at) AS day, COALESCE(SUM(qty), 0) AS cnt
         FROM quality_inspection_defects
         WHERE company_id = ?
           AND date(created_at) BETWEEN ? AND ?
         GROUP BY day`
      )
      .all(companyId, range.from, range.to);

    const defectsMap = toCountMap(defectsDailyRows, 'day');
    const lastDay = range.to;
    const prevDate = addDays(range.toDate, -1);
    const prevDay = prevDate >= range.fromDate ? formatDate(prevDate) : null;

    const alerts = [];
    const defectRatePct = calcDefectRatePct(production.goodQty || 0, production.defectQty || 0);
    const defectRate = (production.goodQty || 0) + (production.defectQty || 0)
      ? (production.defectQty || 0) / ((production.goodQty || 0) + (production.defectQty || 0))
      : 0;

    if (defectRate > threshold) {
      alerts.push({
        type: 'DEFECT_RATE_HIGH',
        valuePct: defectRatePct,
        threshold,
      });
    }

    if (prevDay) {
      const prevCnt = defectsMap.get(prevDay) || 0;
      const lastCnt = defectsMap.get(lastDay) || 0;
      if (prevCnt > 0 && lastCnt >= prevCnt * 2) {
        alerts.push({
          type: 'INSPECTION_DEFECT_SPIKE',
          previousDate: prevDay,
          previousCount: prevCnt,
          lastDate: lastDay,
          lastCount: lastCnt,
        });
      }
    }

    return res.json(
      ok({
        from: range.from,
        to: range.to,
        defectRateThreshold: threshold,
        alerts,
        metrics: {
          productionGoodQty: production.goodQty || 0,
          productionDefectQty: production.defectQty || 0,
          defectRatePct,
          inspectionsTotal: inspections.cnt || 0,
          inspectionDefectsTotal: inspectionDefects.cnt || 0,
        },
      })
    );
  }

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

// GET /api/v1/dashboard/telemetry-status
router.get('/telemetry-status', (req, res) => {
  const companyId = req.companyId;
  const staleMinutes = getStaleMinutes();
  const rows = db
    .prepare(
      `SELECT id, device_key_last_seen_at as lastSeenAt
       FROM equipments
       WHERE company_id = ?`
    )
    .all(companyId);

  let okCount = 0;
  let warningCount = 0;
  let neverCount = 0;
  const now = Date.now();

  for (const row of rows) {
    if (!row.lastSeenAt) {
      neverCount += 1;
      continue;
    }
    const last = new Date(row.lastSeenAt);
    if (Number.isNaN(last.getTime())) {
      neverCount += 1;
      continue;
    }
    const diffMin = (now - last.getTime()) / 60000;
    if (diffMin > staleMinutes) {
      warningCount += 1;
    } else {
      okCount += 1;
    }
  }

  return res.json(
    ok({
      staleMinutes,
      lastComputedAt: new Date().toISOString(),
      counts: {
        ok: okCount,
        warning: warningCount,
        never: neverCount,
      },
    })
  );
});

module.exports = router;
