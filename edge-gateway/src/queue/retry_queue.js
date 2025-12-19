const fs = require('fs');
const path = require('path');

function enqueueRetry(dir, payload, reason) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(dir, `retry_${ts}.json`);
  const entry = {
    reason: reason || 'unknown',
    payload,
    createdAt: new Date().toISOString(),
  };
  fs.writeFileSync(file, JSON.stringify(entry), 'utf8');
}

module.exports = { enqueueRetry };