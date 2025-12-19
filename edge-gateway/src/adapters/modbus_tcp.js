function readModbusTcp(profile) {
  // Placeholder for real Modbus TCP implementation.
  // Returns simulated metrics for now.
  const metrics = {};
  for (const metric of profile.metrics || []) {
    metrics[metric.name] = Number((Math.random() * 100).toFixed(2));
  }
  return Promise.resolve({
    adapter: 'modbus_tcp',
    equipmentCode: profile.equipmentCode,
    metrics,
  });
}

module.exports = { readModbusTcp };