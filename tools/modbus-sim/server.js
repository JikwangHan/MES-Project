const fs = require('fs');
const net = require('net');
const path = require('path');

function parseArgs(argv) {
  const args = { profile: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--profile') {
      args.profile = argv[i + 1];
      i += 1;
    }
  }
  return args;
}

function loadProfile(profilePath) {
  if (!fs.existsSync(profilePath)) {
    throw new Error(`Profile not found: ${profilePath}`);
  }
  const raw = fs.readFileSync(profilePath, 'utf8');
  return JSON.parse(raw);
}

function buildRegisters(profile) {
  const input = profile.holdingRegisters || [];
  if (Array.isArray(input)) {
    return input.slice();
  }
  const regs = [];
  Object.keys(input).forEach((key) => {
    const addr = Number(key);
    if (Number.isNaN(addr)) {
      return;
    }
    regs[addr] = Number(input[key]) || 0;
  });
  return regs;
}

function handleRequest(socket, buffer, registers) {
  if (buffer.length < 7) {
    return null;
  }
  const len = buffer.readUInt16BE(4);
  const frameLen = 6 + len;
  if (buffer.length < frameLen) {
    return null;
  }

  const frame = buffer.slice(0, frameLen);
  const transactionId = frame.readUInt16BE(0);
  const unitId = frame[6];
  const pdu = frame.slice(7);
  const functionCode = pdu[0];

  if (functionCode === 3 || functionCode === 4) {
    const start = pdu.readUInt16BE(1);
    const qty = pdu.readUInt16BE(3);
    const byteCount = qty * 2;

    const response = Buffer.alloc(9 + byteCount);
    response.writeUInt16BE(transactionId, 0);
    response.writeUInt16BE(0, 2);
    response.writeUInt16BE(3 + byteCount, 4);
    response[6] = unitId;
    response[7] = functionCode;
    response[8] = byteCount;

    for (let i = 0; i < qty; i += 1) {
      const reg = registers[start + i] ?? 0;
      response.writeUInt16BE(reg, 9 + i * 2);
    }

    socket.write(response);
    return frameLen;
  }

  const exception = Buffer.alloc(9);
  exception.writeUInt16BE(transactionId, 0);
  exception.writeUInt16BE(0, 2);
  exception.writeUInt16BE(3, 4);
  exception[6] = unitId;
  exception[7] = functionCode + 0x80;
  exception[8] = 1;
  socket.write(exception);
  return frameLen;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const defaultProfile = path.join(__dirname, 'profiles', 'sample_modbus_tcp_sim.json');
  const profilePath = path.resolve(args.profile || defaultProfile);
  const profile = loadProfile(profilePath);
  const registers = buildRegisters(profile);
  const port = Number(profile.port || 1502);

  const server = net.createServer((socket) => {
    let buffer = Buffer.alloc(0);
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      let consumed;
      do {
        consumed = handleRequest(socket, buffer, registers);
        if (consumed) {
          buffer = buffer.slice(consumed);
        }
      } while (consumed);
    });
  });

  server.listen(port, () => {
    console.log(`[modbus-sim] listening on ${port}`);
    console.log(`[modbus-sim] profile=${profilePath}`);
  });
}

main();
