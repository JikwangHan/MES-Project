# Edge Gateway (Ticket-17)

This is a standalone gateway service for southbound device adapters (Modbus TCP/RTU, Serial) and uplink to MES telemetry.
It is intentionally separated from the MES server runtime and release gate.

## Quick start (local)

1) Start MES server (in repo root):

```
$env:MES_MASTER_KEY="dev-master-key"
node src/server.js
```

2) Run gateway once:

```
cd edge-gateway
$env:MES_BASE_URL="http://localhost:4000"
$env:MES_COMPANY_ID="COMPANY-A"
node src/index.js --once
```

You should see an uplink success log and one telemetry event inserted.

## Environment variables

- MES_BASE_URL: MES server base URL (default: http://localhost:4000)
- MES_COMPANY_ID: companyId header value (default: COMPANY-A)
- MES_ROLE: role header value (default: VIEWER)
- MES_DEVICE_KEY: device key id (required when signing enabled)
- MES_DEVICE_SECRET: device secret (required when signing enabled)
- MES_SIGNING_ENABLED: 1 to enable signing (default: 0)

- GATEWAY_PROFILE: config profile name (default: sample_modbus_tcp)
- GATEWAY_POLL_MS: poll interval in milliseconds (default: 1000)
- GATEWAY_RAWLOG_DIR: raw log directory
- GATEWAY_RETRY_DIR: retry queue directory

## Config


## Smoke test

```
cd edge-gateway
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/smoke-gateway.ps1
```

Notes:
- Modbus RTU adapter is a stub for now.
