const fs = require('fs');
const path = require('path');
const { loadProfile } = require('./config');
const { readModbusTcp } = require('./adapters/modbus_tcp');
const { readModbusRtu } = require('./adapters/modbus_rtu');
const { normalizeTelemetry } = require('./normalizer/normalize');
const { sendTelemetry } = require('./uplink/mes_telemetry_client');
const { writeRawLog } = require('./log/raw_log_store');
const { enqueueRetry } = require('./queue/retry_queue');

const args = process.argv.slice(2);
const runOnce = args.includes('--once');

const env = {
  baseUrl: process.env.MES_BASE_URL || 'http://localhost:4000',
  companyId: process.env.MES_COMPANY_ID || 'COMPANY-A',
  role: process.env.MES_ROLE || 'VIEWER',
  deviceKeyId: process.env.MES_DEVICE_KEY || '',
  deviceSecret: process.env.MES_DEVICE_SECRET || '',
  signingEnabled: process.env.MES_SIGNING_ENABLED === '1',
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

async function readFromAdapter(profile) {
  if (profile.adapter === 'modbus_tcp') {
    return readModbusTcp(profile);
  }
  if (profile.adapter === 'modbus_rtu') {
    return readModbusRtu(profile);
  }
  throw new Error(`Unsupported adapter: ${profile.adapter}`);
}

async function runCycle() {
  const profile = loadProfile(env.profile);
  const metrics = await readFromAdapter(profile);
  const payload = normalizeTelemetry(profile, metrics);

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
      payload,
    });
    if (!result.ok) {
      enqueueRetry(env.retryDir, payload, result.error);
      throw new Error(result.error || 'uplink failed');
    }
    console.log('[gateway] uplink ok', result.status);
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