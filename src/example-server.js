const http = require('http');

const PORT = 4000;

// 가장 단순한 HTTP 서버 예제
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('MES Project 서버가 정상 동작 중입니다.');
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
