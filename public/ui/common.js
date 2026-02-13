(function () {
  const KEY_BASE_URL = "mes_ui_base_url";
  const KEY_COMPANY = "mes_ui_company";
  const KEY_ROLE = "mes_ui_role";

  function getConfig() {
    return {
      baseUrl: localStorage.getItem(KEY_BASE_URL) || "",
      companyId: localStorage.getItem(KEY_COMPANY) || "COMPANY-A",
      role: (localStorage.getItem(KEY_ROLE) || "VIEWER").toUpperCase(),
    };
  }

  function setConfig(cfg) {
    localStorage.setItem(KEY_BASE_URL, cfg.baseUrl || "");
    localStorage.setItem(KEY_COMPANY, cfg.companyId || "COMPANY-A");
    localStorage.setItem(KEY_ROLE, (cfg.role || "VIEWER").toUpperCase());
  }

  function buildUrl(path) {
    const cfg = getConfig();
    const base = (cfg.baseUrl || "").replace(/\/$/, "");
    if (!base) return path;
    return base + path;
  }

  async function apiFetch(path) {
    const cfg = getConfig();
    const res = await fetch(buildUrl(path), {
      method: "GET",
      headers: {
        "x-company-id": cfg.companyId,
        "x-role": cfg.role,
      },
    });
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch (_err) {
      throw new Error("JSON 파싱 실패\n" + text);
    }
    if (!res.ok || !data.success) {
      throw new Error("API 실패 (" + res.status + ")\n" + JSON.stringify(data, null, 2));
    }
    return data.data;
  }

  function formatDate(value) {
    if (!value) return "-";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return "-";
    return d.toLocaleString();
  }

  function statusBadge(status) {
    const s = (status || "NEVER").toUpperCase();
    const cls = s === "OK" ? "ok" : s === "WARNING" ? "warning" : "never";
    return '<span class="badge ' + cls + '">' + s + "</span>";
  }

  function mountConfig(containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;
    const cfg = getConfig();
    el.innerHTML =
      '<div class="panel"><h2>API 연결 설정</h2>' +
      '<div class="row">' +
      '<label>Base URL <input id="cfgBaseUrl" placeholder="예: http://192.168.219.110" value="' + cfg.baseUrl + '"></label>' +
      '<label>Company <input id="cfgCompany" value="' + cfg.companyId + '"></label>' +
      '<label>Role <select id="cfgRole"><option>VIEWER</option><option>OPERATOR</option><option>MANAGER</option></select></label>' +
      '<button id="cfgSaveBtn">저장/새로고침</button>' +
      "</div></div>";

    const roleSel = document.getElementById("cfgRole");
    roleSel.value = cfg.role;

    document.getElementById("cfgSaveBtn").addEventListener("click", function () {
      setConfig({
        baseUrl: document.getElementById("cfgBaseUrl").value.trim(),
        companyId: document.getElementById("cfgCompany").value.trim(),
        role: document.getElementById("cfgRole").value,
      });
      location.reload();
    });
  }

  function showError(targetId, err) {
    const el = document.getElementById(targetId);
    if (!el) return;
    el.innerHTML = '<div class="error">' + (err && err.message ? err.message : String(err)) + "</div>";
  }

  window.MESUI = {
    apiFetch,
    formatDate,
    statusBadge,
    mountConfig,
    showError,
    getConfig,
  };
})();
