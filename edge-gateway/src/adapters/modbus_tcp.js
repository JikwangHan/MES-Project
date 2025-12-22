// Modbus TCP adapter skeleton (P0)
// NOTE: This is a stub. Real implementation should wire a Modbus client.

class ModbusTcpAdapter {
  constructor(options = {}) {
    this.host = options.host || '127.0.0.1';
    this.port = options.port || 502;
    this.unitId = options.unitId || 1;
    this.devMode = options.devMode === true;
  }

  async connect() {
    if (this.devMode) {
      return true;
    }
    throw new Error('modbus_tcp connect not implemented');
  }

  async readMetrics(map = []) {
    if (this.devMode) {
      const metrics = {};
      for (const point of map) {
        if (!point || !point.name) {
          continue;
        }
        metrics[point.name] = 0;
      }
      return metrics;
    }
    throw new Error('modbus_tcp read not implemented');
  }

  async close() {
    return true;
  }
}

module.exports = { ModbusTcpAdapter };
