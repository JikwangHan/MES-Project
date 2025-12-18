\
#!/usr/bin/env bash
set -euo pipefail

# tools/erd/render_erd.sh
# ------------------------------------------------------------
# 목적: Mermaid ERD(.mmd) -> PNG/PDF 렌더링(Linux/Mac)

MMD="${ERD_MMD:-docs/erd/mes_erd.mmd}"
OUTDIR="${ERD_OUTDIR:-docs/erd}"

if [ ! -f "$MMD" ]; then
  echo "[ERD] Mermaid 파일이 없습니다: $MMD"
  echo "[ERD] 먼저 생성하세요: node tools/erd/generate_erd.js"
  exit 2
fi

mkdir -p "$OUTDIR"

PNG="$OUTDIR/mes_erd.png"
PDF="$OUTDIR/mes_erd.pdf"

echo "[ERD] PNG 렌더링: $PNG"
npx -y @mermaid-js/mermaid-cli@latest -i "$MMD" -o "$PNG"

echo "[ERD] PDF 렌더링: $PDF"
npx -y @mermaid-js/mermaid-cli@latest -i "$MMD" -o "$PDF"

echo "[ERD] 완료"
echo " - $PNG"
echo " - $PDF"
