const fs = require('fs');
const path = require('path');

const configDir = path.join(__dirname, '..', 'config');

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
    const mapPath = path.isAbsolute(profile.registerMapFile)
      ? profile.registerMapFile
      : path.join(configDir, profile.registerMapFile);
    if (!fs.existsSync(mapPath)) {
      throw new Error(`Register map not found: ${mapPath}`);
    }
    const mapRaw = fs.readFileSync(mapPath, 'utf8');
    profile.registerMap = JSON.parse(mapRaw);
  }
  return profile;
}

module.exports = { loadProfile };
