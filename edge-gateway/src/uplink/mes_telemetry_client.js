const crypto = require('crypto');

function sha256Hex(str) {
  return crypto.createHash('sha256').update(str, 'utf8').digest('hex');
}

function hmac256Hex(secret, msg) {
  return crypto.createHmac('sha256', secret).update(msg, 'utf8').digest('hex');
}

function buildSignature({ companyId, deviceKeyId, deviceSecret, ts, nonce, bodyRaw }) {
  const bodyHash = sha256Hex(bodyRaw);
  const canonical = [companyId, deviceKeyId, String(ts), nonce, bodyHash].join('\n');
  return hmac256Hex(deviceSecret, canonical);
}

async function sendTelemetry({
  baseUrl,
  companyId,
  role,
  deviceKeyId,
  deviceSecret,
  signingEnabled,
  canonical,
  payload,
}) {
  const bodyRaw = JSON.stringify(payload);
  const headers = {
    'Content-Type': 'application/json',
    'x-company-id': companyId,
    'x-role': role,
  };
  if (canonical) {
    headers['x-canonical'] = canonical;
  }

  if (signingEnabled) {
    if (!deviceKeyId || !deviceSecret) {
      return { ok: false, status: 0, error: 'missing device key/secret' };
    }
    const ts = Math.floor(Date.now() / 1000);
    const nonce = crypto.randomUUID().replace(/-/g, '');
    const signature = buildSignature({
      companyId,
      deviceKeyId,
      deviceSecret,
      ts,
      nonce,
      bodyRaw,
    });
    headers['x-device-key'] = deviceKeyId;
    headers['x-ts'] = String(ts);
    headers['x-nonce'] = nonce;
    headers['x-signature'] = signature;
  }

  const res = await fetch(`${baseUrl}/api/v1/telemetry/events`, {
    method: 'POST',
    headers,
    body: bodyRaw,
  });

  if (!res.ok) {
    const text = await res.text();
    return { ok: false, status: res.status, error: text };
  }

  return { ok: true, status: res.status };
}

module.exports = { sendTelemetry };
