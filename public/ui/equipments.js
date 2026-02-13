function getQueryStatus() {
  const p = new URLSearchParams(location.search);
  return (p.get("status") || "ALL").toUpperCase();
}

async function loadEquipments() {
  try {
    const status = document.getElementById("statusFilter").value;
    const q = status === "ALL" ? "" : ("?status=" + encodeURIComponent(status));
    const items = await MESUI.apiFetch("/api/v1/equipments" + q);
    const body = document.getElementById("listBody");
    body.innerHTML = "";

    items.forEach(function (item) {
      const tr = document.createElement("tr");
      if (item.status === "WARNING" || item.status === "NEVER") {
        tr.style.fontWeight = "700";
      }
      tr.innerHTML =
        "<td><a href=\"./equipment-detail.html?id=" + item.id + "\">" + (item.name || "-") + "</a></td>" +
        "<td>" + (item.deviceKeyId || "-") + "</td>" +
        "<td>" + MESUI.formatDate(item.lastSeenAt) + "</td>" +
        "<td>" + MESUI.statusBadge(item.status) + "</td>";
      body.appendChild(tr);
    });
  } catch (err) {
    MESUI.showError("errorRoot", err);
  }
}

(function () {
  MESUI.mountConfig("configRoot");
  const qStatus = getQueryStatus();
  document.getElementById("statusFilter").value = ["OK", "WARNING", "NEVER"].includes(qStatus) ? qStatus : "ALL";
  document.getElementById("applyBtn").addEventListener("click", loadEquipments);
  loadEquipments();
})();
