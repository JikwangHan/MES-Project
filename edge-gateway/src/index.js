const fs = require('fs');
const path = require('path');
const { loadProfile } = require('./config');
const { normalizeTelemetry } = require('./normalizer/normalize');
const { sendTelemetry } = require('./uplink/mes_telemetry_client');
const { writeRawLog } = require('./log/raw_log_store');
const { enqueueRetry } = require('./queue/retry_queue');
const { ModbusTcpAdapter } = require('./adapters/modbus_tcp');

const args = process.argv.slice(2);
const runOnce = args.includes('--once');

const env = {
  baseUrl: process.env.MES_BASE_URL || 'http://localhost:4000',
  companyId: process.env.MES_COMPANY_ID || 'COMPANY-A',
  role: process.env.MES_ROLE || 'VIEWER',
  deviceKeyId: process.env.MES_DEVICE_KEY || '',
  deviceSecret: process.env.MES_DEVICE_SECRET || '',
  signingEnabled: process.env.MES_SIGNING_ENABLED === '1',
  canonical: process.env.MES_CANONICAL || 'stable-json',
  pollMs: Number(process.env.GATEWAY_POLL_MS || 1000),
  rawDir: process.env.GATEWAY_RAWLOG_DIR || path.join(__dirname, '..', 'data', 'rawlogs'),
  retryDir: process.env.GATEWAY_RETRY_DIR || path.join(__dirname, '..', 'data', 'retry'),
  profile: process.env.GATEWAY_PROFILE || 'sample_modbus_tcp',
};

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function stubMetricValue(type) {
  switch (String(type || '').toLowerCase()) {
    case 'float':
      return 12.34;
    case 'int':
      return 123;
    case 'bool':
      return true;
    default:
      return 0;
  }
}

async function readFromAdapter(profile) {
  if (profile.adapter === 'modbus_tcp' || profile.adapter === 'modbus_rtu') {
    if (profile.adapter === 'modbus_tcp') {
      const adapter = new ModbusTcpAdapter({
        ...(profile.connection || {}),
        devMode: profile.devMode === true,
      });
      await adapter.connect();
      const map = Array.isArray(profile.metrics) ? profile.metrics : [];
      const metrics = await adapter.readMetrics(map);
      await adapter.close();
      return {
        adapter: profile.adapter,
        equipmentCode: profile.equipmentCode,
        metrics,
      };
    }

    const metrics = {};
    const items = Array.isArray(profile.metrics) ? profile.metrics : [];
    for (const item of items) {
      if (!item || !item.name) {
        continue;
      }
      metrics[item.name] = stubMetricValue(item.type);
    }
    return {
      adapter: profile.adapter,
      equipmentCode: profile.equipmentCode,
      metrics,
    };
  }
  throw new Error(`Unsupported adapter: ${profile.adapter}`);
}

async function runCycle() {
  const profile = loadProfile(env.profile);
  let adapterResult;
  try {
    adapterResult = await readFromAdapter(profile);
    if (env.profile === 'sample_modbus_tcp') {
      console.log('[PASS] Ticket-17.3-01 adapter connect');
      console.log('[PASS] Ticket-17.3-02 register map load');
    }
  } catch (err) {
    if (env.profile === 'sample_modbus_tcp') {
      console.error('[FAIL] Ticket-17.3-01 adapter connect');
    }
    throw err;
  }
  const payload = normalizeTelemetry(profile, adapterResult);
  if (env.profile === 'sample_modbus_tcp') {
    console.log('[PASS] Ticket-17.3-03 normalize payload');
  }

  ensureDir(env.rawDir);
  ensureDir(env.retryDir);

  writeRawLog(env.rawDir, payload);

  try {
    const result = await sendTelemetry({
      baseUrl: env.baseUrl,
      companyId: env.companyId,
      role: env.role,
      deviceKeyId: env.deviceKeyId,
      deviceSecret: env.deviceSecret,
      signingEnabled: env.signingEnabled,
      canonical: env.canonical,
      payload,
    });
    if (!result.ok) {
      enqueueRetry(env.retryDir, payload, result.error);
      if (env.profile === 'sample_modbus_tcp') {
        console.error('[FAIL] Ticket-17.3-04 uplink');
      }
      throw new Error(result.error || 'uplink failed');
    }
    console.log('[gateway] uplink ok', result.status);
    if (env.profile === 'sample_modbus_tcp') {
      console.log('[PASS] Ticket-17.3-04 uplink');
    }
  } catch (err) {
    console.error('[gateway] uplink error', err.message);
    if (runOnce) {
      process.exit(1);
    }
  }
}

async function main() {
  if (runOnce) {
    await runCycle();
    return;
  }

  console.log('[gateway] started', {
    baseUrl: env.baseUrl,
    companyId: env.companyId,
    profile: env.profile,
    pollMs: env.pollMs,
  });

  await runCycle();
  setInterval(runCycle, env.pollMs);
}

main().catch((err) => {
  console.error('[gateway] fatal', err.message);
  process.exit(1);
});
