// 역할 확인: VIEWER는 쓰기 불가
const getRoleFromHeader = (req) => {
  // x-role 헤더에서 역할을 받습니다. 기본값 VIEWER
  const role = (req.headers['x-role'] || 'VIEWER').toUpperCase();
  return role;
};

const attachRole = (req, _res, next) => {
  req.userRole = getRoleFromHeader(req);
  next();
};

const ensureNotViewer = (req, res, next) => {
  const role = req.userRole || getRoleFromHeader(req);
  if (role === 'VIEWER') {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'VIEWER 권한은 등록/수정이 불가합니다.' },
    });
  }
  next();
};

module.exports = { attachRole, ensureNotViewer };
