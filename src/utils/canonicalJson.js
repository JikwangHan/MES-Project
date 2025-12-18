const isPlainObject = (value) =>
  value !== null && typeof value === 'object' && !Array.isArray(value);

const normalize = (value) => {
  if (Array.isArray(value)) {
    return value.map((item) => normalize(item));
  }

  if (isPlainObject(value)) {
    const keys = Object.keys(value).sort();
    const out = {};
    for (const key of keys) {
      out[key] = normalize(value[key]);
    }
    return out;
  }

  return value;
};

const stableStringify = (value) => {
  const normalized = normalize(value);
  return JSON.stringify(normalized);
};

module.exports = {
  stableStringify,
};
