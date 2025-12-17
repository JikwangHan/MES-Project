// 회사 구분용 멀티테넌트 헬퍼
module.exports = function tenantMiddleware(req, res, next) {
  const companyId = req.headers['x-company-id'];
  if (!companyId) {
    return res.status(400).json({
      success: false,
      error: { code: 'COMPANY_REQUIRED', message: '요청 헤더 x-company-id 가 필요합니다.' },
    });
  }
  req.companyId = companyId;
  next();
};
