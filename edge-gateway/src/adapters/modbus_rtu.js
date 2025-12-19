function buildMetrics(points) {
  const metrics = {};
  for (const point of points) {
    const name = point.name || `addr_${point.address}`;
    let value = Math.random() * 100;
    if (point.type === 'bool') {
      value = Math.random() > 0.5 ? 1 : 0;
    } else if (point.type === 'int') {
      value = Math.floor(Math.random() * 100);
    }
    if (typeof point.scale === 'number') {
      value = value * point.scale;
    }
    metrics[name] = Number(value.toFixed(2));
  }
  return metrics;
}

function createModbusRtuAdapter(profile) {
  const connection = profile.connection || {};
  const serial = profile.serial || {};
  const points =
    (profile.registerMap && profile.registerMap.points) || profile.metrics || [];

  return {
    async connect() {
      // Stub for Modbus RTU (RS-485/RS-232). Real serial implementation later.
      return {
        port: serial.port,
        baudRate: serial.baudRate,
        parity: serial.parity,
        dataBits: serial.dataBits,
        stopBits: serial.stopBits,
        timeoutMs: serial.timeoutMs,
        unitId: connection.unitId,
      };
    },
    async readPoints() {
      const metrics = buildMetrics(points);
      return {
        adapter: 'modbus_rtu',
        equipmentCode: profile.equipmentCode,
        metrics,
      };
    },
    async close() {
      return undefined;
    },
  };
}

module.exports = { createModbusRtuAdapter };
