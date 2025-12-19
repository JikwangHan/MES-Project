const { purgeReportKpiCacheNow } = require('../db');

const getEnvNumber = (name, fallback) => {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return fallback;
  }
  const value = Number(raw);
  if (!Number.isFinite(value)) return fallback;
  return Math.floor(value);
};

const purgeOnce = () => {
  const maxRows = getEnvNumber('REPORT_KPI_CACHE_MAX_ROWS_PER_COMPANY', 50000);
  purgeReportKpiCacheNow({ maxRowsPerCompany: maxRows });
};

const startReportKpiCachePurgeScheduler = () => {
  const enabled = getEnvNumber('REPORT_KPI_CACHE_PURGE_ENABLED', 1) === 1;
  if (!enabled) return;

  const runOnStart = getEnvNumber('REPORT_KPI_CACHE_PURGE_ON_START', 1) === 1;
  const intervalSeconds = getEnvNumber('REPORT_KPI_CACHE_PURGE_INTERVAL_SECONDS', 3600);

  if (runOnStart) {
    try {
      purgeOnce();
    } catch (err) {
      console.warn('[WARN] report KPI cache purge (startup) failed:', err.message);
    }
  }

  if (intervalSeconds <= 0) return;

  setInterval(() => {
    try {
      purgeOnce();
    } catch (err) {
      console.warn('[WARN] report KPI cache purge failed:', err.message);
    }
  }, intervalSeconds * 1000);
};

module.exports = {
  startReportKpiCachePurgeScheduler,
};
