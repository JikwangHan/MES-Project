const fs = require('fs');
const path = require('path');

function writeRawLog(dir, payload) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(dir, `raw_${ts}.json`);
  fs.writeFileSync(file, JSON.stringify(payload), 'utf8');
}

module.exports = { writeRawLog };