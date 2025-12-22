function getStaleMinutes() {
  const value = Number(process.env.TELEMETRY_STALE_MIN || 5);
  return Number.isFinite(value) && value > 0 ? value : 5;
}

function getStatus(lastSeenAt, staleMinutes) {
  if (!lastSeenAt) return 'NEVER';
  const parsed = new Date(lastSeenAt);
  if (Number.isNaN(parsed.getTime())) return 'NEVER';
  const diffMin = (Date.now() - parsed.getTime()) / 60000;
  return diffMin > staleMinutes ? 'WARNING' : 'OK';
}

module.exports = { getStaleMinutes, getStatus };
