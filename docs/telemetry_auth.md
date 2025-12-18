# Telemetry 인증 규칙 (운영형)

이 문서는 게이트웨이/장비가 Telemetry 이벤트를 전송할 때 사용하는 **서명 규칙**과 **헤더 규칙**을 설명합니다.

## 1) 필수 헤더

- `x-company-id`: 테넌트 식별자
- `x-device-key`: 장비 키 ID
- `x-ts`: 요청 생성 시각(Unix epoch seconds)
- `x-nonce`: 재사용 불가 난수(권장: 16~32 bytes)
- `x-signature`: HMAC-SHA256 서명(hex)

## 2) Canonical 규칙(고정)

서명은 **JSON 압축 문자열(JSON.stringify(body)) 기준**으로 계산합니다.

1) `bodyCanonical = JSON.stringify(body)`
2) `bodyHash = SHA256_HEX(bodyCanonical)`
3) `canonical = companyId + "\n" + deviceKeyId + "\n" + ts + "\n" + nonce + "\n" + bodyHash`
4) `signature = HMAC_SHA256_HEX(secret, canonical)`

## 3) Node.js 샘플

```js
const crypto = require('crypto');

function sha256Hex(s) {
  return crypto.createHash('sha256').update(s, 'utf8').digest('hex');
}
function hmac256Hex(secret, msg) {
  return crypto.createHmac('sha256', secret).update(msg, 'utf8').digest('hex');
}

function signTelemetry({ companyId, deviceKeyId, secret, ts, nonce, body }) {
  const bodyCanonical = JSON.stringify(body);
  const bodyHash = sha256Hex(bodyCanonical);
  const canonical = [companyId, deviceKeyId, String(ts), nonce, bodyHash].join('\n');
  return hmac256Hex(secret, canonical);
}
```

## 4) Python 샘플

```py
import hmac, hashlib, json

def sha256_hex(s: str) -> str:
  return hashlib.sha256(s.encode('utf-8')).hexdigest()

def hmac_sha256_hex(secret: str, msg: str) -> str:
  return hmac.new(secret.encode('utf-8'), msg.encode('utf-8'), hashlib.sha256).hexdigest()

def sign_telemetry(company_id, device_key_id, secret, ts, nonce, body):
  body_canonical = json.dumps(body, separators=(',', ':'), ensure_ascii=False)
  body_hash = sha256_hex(body_canonical)
  canonical = "\n".join([company_id, device_key_id, str(ts), nonce, body_hash])
  return hmac_sha256_hex(secret, canonical)
```

## 5) C# 샘플

```csharp
using System;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

static string Sha256Hex(string s) {
  using var sha = SHA256.Create();
  var hash = sha.ComputeHash(Encoding.UTF8.GetBytes(s));
  return Convert.ToHexString(hash).ToLowerInvariant();
}

static string HmacSha256Hex(string secret, string msg) {
  using var h = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
  var sig = h.ComputeHash(Encoding.UTF8.GetBytes(msg));
  return Convert.ToHexString(sig).ToLowerInvariant();
}

static string SignTelemetry(string companyId, string deviceKeyId, string secret, long ts, string nonce, object body) {
  var bodyCanonical = JsonSerializer.Serialize(body, new JsonSerializerOptions { WriteIndented = false });
  var bodyHash = Sha256Hex(bodyCanonical);
  var canonical = string.Join("\n", companyId, deviceKeyId, ts.ToString(), nonce, bodyHash);
  return HmacSha256Hex(secret, canonical);
}
```

## 6) 비-Node 환경 주의사항

- JSON 키 순서가 라이브러리마다 달라질 수 있습니다.
- 서버는 **JSON 압축 문자열(JSON.stringify)** 기준으로 서명 검증을 하므로,
  - Python: `json.dumps(..., separators=(',', ':'))`
  - C#: `JsonSerializer`에서 공백 제거 옵션 사용
- 키 순서가 달라지는 환경에서는 **키 정렬(정규화 JSON)** 정책을 별도 합의해야 합니다.

