// Modbus TCP adapter (P0).
// NOTE: Real connection requires the "modbus-serial" package to be installed.

function safeRequireModbusSerial() {
  try {
    // eslint-disable-next-line global-require
    return require('modbus-serial');
  } catch (err) {
    throw new Error('modbus-serial is not installed. Run: cd edge-gateway && npm install');
  }
}

function pointLength(type) {
  const normalized = String(type || '').toLowerCase();
  if (normalized === 'float' || normalized === 'float32') {
    return 2;
  }
  return 1;
}

function parseRegisterValue(type, regs, offset, scale) {
  const normalized = String(type || '').toLowerCase();
  let value;
  if (normalized === 'float' || normalized === 'float32') {
    const hi = regs[offset] ?? 0;
    const lo = regs[offset + 1] ?? 0;
    const buf = Buffer.alloc(4);
    buf.writeUInt16BE(hi, 0);
    buf.writeUInt16BE(lo, 2);
    value = buf.readFloatBE(0);
  } else if (normalized === 'bool' || normalized === 'boolean') {
    value = (regs[offset] ?? 0) !== 0;
  } else if (normalized === 'int' || normalized === 'int16') {
    const raw = regs[offset] ?? 0;
    value = raw > 32767 ? raw - 65536 : raw;
  } else if (normalized === 'uint' || normalized === 'uint16') {
    value = regs[offset] ?? 0;
  } else {
    value = regs[offset] ?? 0;
  }

  const scaleValue = Number(scale);
  if (!Number.isNaN(scaleValue) && scaleValue !== 0) {
    if (typeof value === 'number') {
      return value * scaleValue;
    }
  }
  return value;
}

class ModbusTcpAdapter {
  constructor(options = {}) {
    this.host = options.host || '127.0.0.1';
    this.port = options.port || 502;
    this.unitId = options.unitId || 1;
    this.devMode = options.devMode === true;
    this.timeoutMs = Number(options.timeoutMs || 3000);
    this.client = null;
  }

  async connect() {
    if (this.devMode) {
      return true;
    }
    const ModbusRTU = safeRequireModbusSerial();
    this.client = new ModbusRTU();
    this.client.setTimeout(this.timeoutMs);
    const delays = [1000, 2000, 5000];
    let lastError;
    for (let i = 0; i < delays.length; i += 1) {
      try {
        await this.client.connectTCP(this.host, { port: this.port });
        this.client.setID(this.unitId);
        return true;
      } catch (err) {
        lastError = err;
        if (i < delays.length - 1) {
          await new Promise((resolve) => setTimeout(resolve, delays[i]));
        }
      }
    }
    throw lastError || new Error('modbus_tcp connect failed');
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
    if (!this.client) {
      throw new Error('modbus_tcp client not connected');
    }
    const points = Array.isArray(map) ? map.filter((p) => p && p.name) : [];
    if (points.length === 0) {
      return {};
    }
    let minAddr = Number.POSITIVE_INFINITY;
    let maxAddr = 0;
    for (const point of points) {
      const addr = Number(point.address);
      if (Number.isNaN(addr)) {
        continue;
      }
      const len = pointLength(point.type);
      minAddr = Math.min(minAddr, addr);
      maxAddr = Math.max(maxAddr, addr + len - 1);
    }
    if (!Number.isFinite(minAddr)) {
      return {};
    }
    const count = maxAddr - minAddr + 1;
    let resp;
    try {
      resp = await this.client.readHoldingRegisters(minAddr, count);
    } catch (err) {
      // One retry for transient read errors.
      resp = await this.client.readHoldingRegisters(minAddr, count);
    }
    const regs = Array.isArray(resp?.data) ? resp.data : [];

    const metrics = {};
    for (const point of points) {
      const addr = Number(point.address);
      if (Number.isNaN(addr)) {
        continue;
      }
      const offset = addr - minAddr;
      metrics[point.name] = parseRegisterValue(point.type, regs, offset, point.scale);
    }
    return metrics;
  }

  async close() {
    if (this.client && typeof this.client.close === 'function') {
      await new Promise((resolve) => {
        this.client.close(() => resolve());
      });
      this.client = null;
    }
    return true;
  }
}

module.exports = { ModbusTcpAdapter };
