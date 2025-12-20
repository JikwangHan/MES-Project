const fs = require('fs');
const path = require('path');

const configDir = path.join(__dirname, '..', 'config');

function loadRegisterMap(mapFile) {
  if (!mapFile) {
    return null;
  }
  const resolved = path.isAbsolute(mapFile) ? mapFile : path.join(configDir, mapFile);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Register map not found: ${resolved}`);
  }
  const raw = fs.readFileSync(resolved, 'utf8');
  return JSON.parse(raw);
}

function loadProfile(profileName) {
  const file = path.join(configDir, `${profileName}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(`Profile not found: ${file}`);
  }
  const raw = fs.readFileSync(file, 'utf8');
  const profile = JSON.parse(raw);
  if (!profile.adapter || !profile.equipmentCode) {
    throw new Error('Profile missing adapter or equipmentCode');
  }

  if (profile.registerMapFile) {
    profile.registerMap = loadRegisterMap(profile.registerMapFile);
  }

  if (!Array.isArray(profile.metrics) || profile.metrics.length === 0) {
    const points = profile.registerMap?.points || [];
    profile.metrics = points.map((p) => ({
      name: p.name,
      address: p.address,
      type: p.type,
    }));
  }

  return profile;
}

module.exports = { loadProfile };
