const express = require('express');
const { init } = require('./db');
const tenantMiddleware = require('./middleware/tenant');
const { attachRole } = require('./middleware/auth');
const itemCategoryRoutes = require('./routes/itemCategories');
const { ok, fail } = require('./utils/response');

const app = express();
const PORT = process.env.PORT || 4000;

// DB 초기화
init();

// 기본 미들웨어
app.use(express.json());
app.use(tenantMiddleware);
app.use(attachRole);

// 라우트
app.use('/api/v1/item-categories', itemCategoryRoutes);

app.get('/health', (_req, res) => res.json(ok({ status: 'ok' })));

// 404 핸들링
app.use((_req, res) => res.status(404).json(fail('NOT_FOUND', '요청한 경로가 없습니다.')));

app.listen(PORT, () => {
  console.log(`MES API server running at http://localhost:${PORT}`);
});
