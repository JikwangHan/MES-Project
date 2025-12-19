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

function createModbusTcpAdapter(profile) {
  const connection = profile.connection || {};
  const points =
    (profile.registerMap && profile.registerMap.points) || profile.metrics || [];

  return {
    async connect() {
      // Placeholder for real Modbus TCP connection.
      return {
        host: connection.host,
        port: connection.port,
        unitId: connection.unitId,
      };
    },
    async readPoints() {
      const metrics = buildMetrics(points);
      return {
        adapter: 'modbus_tcp',
        equipmentCode: profile.equipmentCode,
        metrics,
      };
    },
    async close() {
      // Placeholder for connection close.
      return undefined;
    },
  };
}

module.exports = { createModbusTcpAdapter };
