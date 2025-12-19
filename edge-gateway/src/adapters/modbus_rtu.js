function readModbusRtu(profile) {
  // Stub for Modbus RTU (RS-485). Real serial implementation will be added later.
  const metrics = {};
  for (const metric of profile.metrics || []) {
    metrics[metric.name] = Number((Math.random() * 100).toFixed(2));
  }
  return Promise.resolve({
    adapter: 'modbus_rtu',
    equipmentCode: profile.equipmentCode,
    metrics,
  });
}

module.exports = { readModbusRtu };