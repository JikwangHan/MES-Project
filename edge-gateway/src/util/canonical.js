function stableStringify(value) {
  if (value === null || value === undefined) {
    return 'null';
  }

  const valueType = typeof value;
  if (valueType === 'number' || valueType === 'boolean') {
    return JSON.stringify(value);
  }
  if (valueType === 'string') {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    const items = value.map((item) => stableStringify(item));
    return `[${items.join(',')}]`;
  }

  const keys = Object.keys(value).sort();
  const pairs = keys.map((key) => {
    const keyJson = JSON.stringify(key);
    const valJson = stableStringify(value[key]);
    return `${keyJson}:${valJson}`;
  });
  return `{${pairs.join(',')}}`;
}

module.exports = { stableStringify };
