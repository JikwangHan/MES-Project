function normalizeTelemetry(profile, adapterResult) {
  const timestamp = new Date().toISOString();
  return {
    equipmentCode: profile.equipmentCode || adapterResult.equipmentCode,
    timestamp,
    eventType: 'TELEMETRY',
    payload: {
      adapter: adapterResult.adapter,
      metrics: adapterResult.metrics,
    },
  };
}

module.exports = { normalizeTelemetry };