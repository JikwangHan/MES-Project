const { cleanupNonces } = require('../db');

const getEnvInt = (name, fallback) => {
  const raw = process.env[name];
  if (raw === undefined || raw === null || raw === '') return fallback;
  const num = Number(raw);
  return Number.isInteger(num) && num >= 0 ? num : fallback;
};

const cleanupNoncesOnce = () => {
  const ttlSeconds = getEnvInt('NONCE_TTL_SECONDS', 86400);
  if (ttlSeconds <= 0) return 0;
  const nowSec = Math.floor(Date.now() / 1000);
  const cutoff = nowSec - ttlSeconds;
  return cleanupNonces(cutoff);
};

const startNonceCleanupScheduler = () => {
  const intervalSeconds = getEnvInt('NONCE_CLEANUP_INTERVAL_SECONDS', 600);
  if (intervalSeconds <= 0) return null;
  return setInterval(() => {
    cleanupNoncesOnce();
  }, intervalSeconds * 1000);
};

module.exports = {
  cleanupNoncesOnce,
  startNonceCleanupScheduler,
};
