const express = require('express');
const { init } = require('./db');
const tenantMiddleware = require('./middleware/tenant');
const { attachRole } = require('./middleware/auth');
const itemCategoryRoutes = require('./routes/itemCategories');
const itemRoutes = require('./routes/items');
const itemBomRoutes = require('./routes/itemBoms');
const processRoutes = require('./routes/processes');
const equipmentRoutes = require('./routes/equipments');
const defectTypeRoutes = require('./routes/defectTypes');
const partnerRoutes = require('./routes/partners');
const telemetryRoutes = require('./routes/telemetry');
const { ok, fail } = require('./utils/response');

const app = express();
const PORT = process.env.PORT || 4000;

// DB 초기화
init();

// 기본 미들웨어
app.use(
  express.json({
    verify: (req, _res, buf) => {
      // Telemetry 서명 검증을 위해 원문 보관
      req.rawBody = buf;
    },
  })
);
app.use(tenantMiddleware);
app.use(attachRole);

// 라우트
app.use('/api/v1/item-categories', itemCategoryRoutes);
app.use('/api/v1/items', itemRoutes);
app.use('/api/v1/items/:itemId/parts', itemBomRoutes);
app.use('/api/v1/processes', processRoutes);
app.use('/api/v1/equipments', equipmentRoutes);
app.use('/api/v1/defect-types', defectTypeRoutes);
app.use('/api/v1/partners', partnerRoutes);
app.use('/api/v1/telemetry', telemetryRoutes);

app.get('/health', (_req, res) => res.json(ok({ status: 'ok' })));

// 404 핸들링
app.use((_req, res) => res.status(404).json(fail('NOT_FOUND', '요청한 경로가 없습니다.')));

app.listen(PORT, () => {
  console.log(`MES API server running at http://localhost:${PORT}`);
});
