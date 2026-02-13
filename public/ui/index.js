(async function () {
  MESUI.mountConfig("configRoot");
  try {
    const data = await MESUI.apiFetch("/api/v1/dashboard/telemetry-status");
    const counts = data.counts || { ok: 0, warning: 0, never: 0 };
    const summary = document.getElementById("summaryRoot");
    summary.innerHTML =
      '<div class="card"><h3>OK</h3><div class="value">' + counts.ok + "</div></div>" +
      '<div class="card warning" id="warningCard"><h3>WARNING</h3><div class="value">' + counts.warning + "</div></div>" +
      '<div class="card"><h3>NEVER</h3><div class="value">' + counts.never + "</div></div>";

    document.getElementById("warningCard").style.cursor = "pointer";
    document.getElementById("warningCard").addEventListener("click", function () {
      location.href = "./equipments.html?status=WARNING";
    });

    document.getElementById("metaRoot").innerHTML =
      "<h2>집계 정보</h2>" +
      '<div class="meta">staleMinutes: ' + data.staleMinutes + "</div>" +
      '<div class="meta">lastComputedAt: ' + MESUI.formatDate(data.lastComputedAt) + "</div>";

    if ((counts.warning || 0) > 0) {
      document.getElementById("warnBanner").innerHTML =
        '<div class="banner">수신 지연(WARNING) 장비가 있습니다. WARNING 카드를 눌러 확인하세요.</div>';
    }
  } catch (err) {
    MESUI.showError("errorRoot", err);
  }
})();
