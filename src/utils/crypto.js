const crypto = require('crypto');

const getMasterKey = () => {
  const key = process.env.MES_MASTER_KEY;
  if (!key) {
    console.error('[MES] MES_MASTER_KEY 환경 변수가 없습니다. 서버를 종료합니다.');
    process.exit(1);
  }
  // 32바이트 키로 맞추기 위해 해시
  return crypto.createHash('sha256').update(key, 'utf8').digest();
};

const encryptSecret = (plain) => {
  const key = getMasterKey();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]).toString('base64'); // iv(12) + tag(16) + data
};

const decryptSecret = (cipherTextB64) => {
  const key = getMasterKey();
  const buf = Buffer.from(cipherTextB64, 'base64');
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const data = buf.subarray(28);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  const dec = Buffer.concat([decipher.update(data), decipher.final()]);
  return dec.toString('utf8');
};

const sha256Hex = (input) =>
  crypto.createHash('sha256').update(input, 'utf8').digest('hex');

const hmacSha256Hex = (secret, input) =>
  crypto.createHmac('sha256', secret).update(input, 'utf8').digest('hex');

const timingSafeEqualHex = (aHex, bHex) => {
  const a = Buffer.from(aHex, 'hex');
  const b = Buffer.from(bHex, 'hex');
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
};

module.exports = {
  encryptSecret,
  decryptSecret,
  sha256Hex,
  hmacSha256Hex,
  timingSafeEqualHex,
  getMasterKey,
};
