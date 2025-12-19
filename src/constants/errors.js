// 공통 오류 코드/메시지 상수
module.exports = {
  VALIDATION_ERROR: { code: 'VALIDATION_ERROR', message: '입력 값이 올바르지 않습니다.' },
  NOT_FOUND: { code: 'NOT_FOUND', message: '요청한 데이터가 없습니다.' },
  CATEGORY_NOT_FOUND: { code: 'CATEGORY_NOT_FOUND', message: 'categoryId가 존재하지 않습니다.' },
  ITEM_NOT_FOUND: { code: 'ITEM_NOT_FOUND', message: 'itemId가 존재하지 않습니다.' },
  FORBIDDEN: { code: 'FORBIDDEN', message: '권한이 없습니다.' },
  DUPLICATE_CODE: { code: 'DUPLICATE_CODE', message: '동일 코드가 이미 존재합니다.' },
  BOM_DUPLICATE: { code: 'BOM_DUPLICATE', message: '이미 동일한 BOM이 존재합니다.' },
  BOM_SELF_REFERENCE: { code: 'BOM_SELF_REFERENCE', message: '완제품과 자재가 동일할 수 없습니다.' },
  PROCESS_CODE_DUPLICATE: { code: 'PROCESS_CODE_DUPLICATE', message: '동일 공정 코드가 이미 존재합니다.' },
  PROCESS_PARENT_NOT_FOUND: { code: 'PROCESS_PARENT_NOT_FOUND', message: 'parent_id가 존재하지 않습니다.' },
  EQUIPMENT_CODE_DUPLICATE: { code: 'EQUIPMENT_CODE_DUPLICATE', message: '동일 설비 코드가 이미 존재합니다.' },
  EQUIPMENT_PROCESS_NOT_FOUND: { code: 'EQUIPMENT_PROCESS_NOT_FOUND', message: 'process_id가 존재하지 않습니다.' },
  DEFECT_CODE_DUPLICATE: { code: 'DEFECT_CODE_DUPLICATE', message: '동일 불량 코드가 이미 존재합니다.' },
  DEFECT_PROCESS_NOT_FOUND: { code: 'DEFECT_PROCESS_NOT_FOUND', message: 'process_id가 존재하지 않습니다.' },
  PARTNER_CODE_DUPLICATE: { code: 'PARTNER_CODE_DUPLICATE', message: '동일 거래처 코드가 이미 존재합니다.' },
  PARTNER_TYPE_INVALID: { code: 'PARTNER_TYPE_INVALID', message: 'type 값이 올바르지 않습니다.' },
  TELEMETRY_EQUIPMENT_CODE_REQUIRED: {
    code: 'TELEMETRY_EQUIPMENT_CODE_REQUIRED',
    message: 'equipmentCode는 필수입니다.',
  },
  TELEMETRY_EQUIPMENT_NOT_FOUND: {
    code: 'TELEMETRY_EQUIPMENT_NOT_FOUND',
    message: '설비를 찾을 수 없습니다.',
  },
  TELEMETRY_AUTH_REQUIRED: {
    code: 'TELEMETRY_AUTH_REQUIRED',
    message: '디바이스 인증 헤더가 필요합니다.',
  },
  TELEMETRY_TS_INVALID: {
    code: 'TELEMETRY_TS_INVALID',
    message: 'x-ts 헤더가 올바르지 않습니다.',
  },
  TELEMETRY_TS_EXPIRED: {
    code: 'TELEMETRY_TS_EXPIRED',
    message: '요청 시간이 허용 범위를 초과했습니다.',
  },
  TELEMETRY_DEVICE_KEY_INVALID: {
    code: 'TELEMETRY_DEVICE_KEY_INVALID',
    message: '디바이스 키가 유효하지 않습니다.',
  },
  TELEMETRY_SIGNATURE_INVALID: {
    code: 'TELEMETRY_SIGNATURE_INVALID',
    message: '서명이 올바르지 않습니다.',
  },
  TELEMETRY_NONCE_REPLAY: {
    code: 'TELEMETRY_NONCE_REPLAY',
    message: '이미 사용된 nonce 입니다.',
  },
  WORK_ORDER_NO_DUPLICATE: {
    code: 'WORK_ORDER_NO_DUPLICATE',
    message: '동일한 작업지시 번호가 이미 존재합니다.',
  },
  WORK_ORDER_REF_NOT_FOUND: {
    code: 'WORK_ORDER_REF_NOT_FOUND',
    message: '참조 정보(item/process/equipment)가 유효하지 않습니다.',
  },
  WORK_ORDER_STATUS_INVALID: {
    code: 'WORK_ORDER_STATUS_INVALID',
    message: '작업지시 상태 값이 올바르지 않습니다.',
  },
  RESULT_QTY_INVALID: {
    code: 'RESULT_QTY_INVALID',
    message: '실적 수량이 올바르지 않습니다.',
  },
  QUALITY_INSPECTION_NO_DUPLICATE: {
    code: 'QUALITY_INSPECTION_NO_DUPLICATE',
    message: '동일한 검사번호가 이미 존재합니다.',
  },
  QUALITY_INSPECTION_TYPE_INVALID: {
    code: 'QUALITY_INSPECTION_TYPE_INVALID',
    message: 'inspectionType 값이 올바르지 않습니다.',
  },
  QUALITY_INSPECTION_STATUS_INVALID: {
    code: 'QUALITY_INSPECTION_STATUS_INVALID',
    message: 'status 값이 올바르지 않습니다.',
  },
  QUALITY_INSPECTION_REF_NOT_FOUND: {
    code: 'QUALITY_INSPECTION_REF_NOT_FOUND',
    message: '참조 정보(workOrder/item/process/equipment)가 유효하지 않습니다.',
  },
  QUALITY_INSPECTION_NOT_FOUND: {
    code: 'QUALITY_INSPECTION_NOT_FOUND',
    message: '검사 정보를 찾을 수 없습니다.',
  },
  QUALITY_DEFECT_QTY_INVALID: {
    code: 'QUALITY_DEFECT_QTY_INVALID',
    message: '불량 수량이 올바르지 않습니다.',
  },
  QUALITY_DEFECT_DUPLICATE: {
    code: 'QUALITY_DEFECT_DUPLICATE',
    message: '이미 동일한 불량 라인이 존재합니다.',
  },
  QUALITY_DEFECT_TYPE_NOT_FOUND: {
    code: 'QUALITY_DEFECT_TYPE_NOT_FOUND',
    message: '불량유형이 유효하지 않습니다.',
  },
  QUALITY_CHECK_ITEM_CODE_DUPLICATE: {
    code: 'QUALITY_CHECK_ITEM_CODE_DUPLICATE',
    message: '동일한 검사 항목 코드가 이미 존재합니다.',
  },
  QUALITY_CHECK_ITEM_TYPE_INVALID: {
    code: 'QUALITY_CHECK_ITEM_TYPE_INVALID',
    message: '검사 항목 타입 값이 올바르지 않습니다.',
  },
  QUALITY_CHECK_ITEM_NOT_FOUND: {
    code: 'QUALITY_CHECK_ITEM_NOT_FOUND',
    message: '검사 항목을 찾을 수 없습니다.',
  },
  QUALITY_RESULT_DUPLICATE: {
    code: 'QUALITY_RESULT_DUPLICATE',
    message: '이미 동일한 검사 결과가 존재합니다.',
  },
  QUALITY_RESULT_VALUE_INVALID: {
    code: 'QUALITY_RESULT_VALUE_INVALID',
    message: '측정값이 올바르지 않습니다.',
  },
  LOT_NO_DUPLICATE: {
    code: 'LOT_NO_DUPLICATE',
    message: '동일한 LOT 번호가 이미 존재합니다.',
  },
  LOT_ITEM_NOT_FOUND: {
    code: 'LOT_ITEM_NOT_FOUND',
    message: '품목 정보가 유효하지 않습니다.',
  },
  LOT_WORK_ORDER_NOT_FOUND: {
    code: 'LOT_WORK_ORDER_NOT_FOUND',
    message: '작업지시 정보가 유효하지 않습니다.',
  },
  LOT_PARENT_NOT_FOUND: {
    code: 'LOT_PARENT_NOT_FOUND',
    message: '상위 LOT 정보를 찾을 수 없습니다.',
  },
  LOT_NOT_FOUND: {
    code: 'LOT_NOT_FOUND',
    message: 'LOT 정보를 찾을 수 없습니다.',
  },
  LOT_TRACE_INVALID: {
    code: 'LOT_TRACE_INVALID',
    message: 'trace 파라미터가 올바르지 않습니다.',
  },
  REPORT_DATE_INVALID: {
    code: 'REPORT_DATE_INVALID',
    message: '날짜 형식이 올바르지 않습니다. (YYYY-MM-DD)',
  },
  REPORT_RANGE_INVALID: {
    code: 'REPORT_RANGE_INVALID',
    message: '날짜 범위가 올바르지 않습니다.',
  },
  REPORT_RANGE_TOO_LARGE: {
    code: 'REPORT_RANGE_TOO_LARGE',
    message: '조회 기간이 너무 깁니다.',
  },
  REPORT_LIMIT_INVALID: {
    code: 'REPORT_LIMIT_INVALID',
    message: 'limit 값이 올바르지 않습니다.',
  },
  DASHBOARD_DAYS_INVALID: {
    code: 'DASHBOARD_DAYS_INVALID',
    message: 'days 값이 올바르지 않습니다.',
  },
  DASHBOARD_LIMIT_INVALID: {
    code: 'DASHBOARD_LIMIT_INVALID',
    message: 'limit 값이 올바르지 않습니다.',
  },
  REPORT_KPI_CACHE_MISS: {
    code: 'REPORT_KPI_CACHE_MISS',
    message: '리포트 캐시가 존재하지 않습니다.',
  },
  WO_LOT_LINK_DUPLICATE: {
    code: 'WO_LOT_LINK_DUPLICATE',
    message: '작업지시와 LOT 링크가 이미 존재합니다.',
  },
  WO_NOT_FOUND: {
    code: 'WO_NOT_FOUND',
    message: '작업지시 정보를 찾을 수 없습니다.',
  },
  QI_LOT_NOT_FOUND: {
    code: 'QI_LOT_NOT_FOUND',
    message: '검사에 연결할 LOT 정보를 찾을 수 없습니다.',
  },
  TELEMETRY_LIMIT_INVALID: {
    code: 'TELEMETRY_LIMIT_INVALID',
    message: 'limit 값이 올바르지 않습니다.',
  },
  SERVER_ERROR: { code: 'SERVER_ERROR', message: '서버 오류가 발생했습니다.' },
};
