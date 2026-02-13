function getId() {
  const p = new URLSearchParams(location.search);
  const raw = p.get("id");
  const id = Number(raw);
  if (!Number.isInteger(id) || id <= 0) return null;
  return id;
}

async function loadDetail() {
  const id = getId();
  if (!id) {
    MESUI.showError("errorRoot", new Error("잘못된 id 입니다. equipments 목록에서 다시 진입하세요."));
    return;
  }

  try {
    const list = await MESUI.apiFetch("/api/v1/equipments");
    const item = list.find(function (x) { return x.id === id; });
    if (!item) {
      throw new Error("장비를 찾을 수 없습니다. id=" + id);
    }

    document.getElementById("headPanel").innerHTML =
      "<h2>장비 정보</h2>" +
      "<div><strong>name:</strong> " + (item.name || "-") + "</div>" +
      "<div><strong>code:</strong> " + (item.code || "-") + "</div>" +
      "<div><strong>status:</strong> " + MESUI.statusBadge(item.status) + "</div>" +
      "<div><strong>lastSeenAt:</strong> " + MESUI.formatDate(item.lastSeenAt) + "</div>";

    const telemetry = await MESUI.apiFetch("/api/v1/equipments/" + id + "/telemetry?limit=20");
    const body = document.getElementById("telemetryBody");
    body.innerHTML = "";
    telemetry.forEach(function (row) {
      const tr = document.createElement("tr");
      tr.innerHTML =
        "<td>" + MESUI.formatDate(row.eventTs) + "</td>" +
        "<td>" + (row.metricCount == null ? "-" : row.metricCount) + "</td>";
      body.appendChild(tr);
    });
  } catch (err) {
    MESUI.showError("errorRoot", err);
  }
}

(function () {
  MESUI.mountConfig("configRoot");
  loadDetail();
})();
