const $ = (id) => document.getElementById(id);

const state = {
  licenses: [],
  events: [],
};

function toast(msg) {
  $("toast").textContent = `${new Date().toLocaleTimeString()} - ${msg}`;
}

function getBaseUrl() {
  return ($("baseUrl").value || window.location.origin).trim().replace(/\/+$/, "");
}

function getAdminKey() {
  return ($("adminKey").value || "").trim();
}

function adminHeaders() {
  return {
    "Content-Type": "application/json",
    "X-Admin-Key": getAdminKey(),
  };
}

function formatDate(value) {
  if (!value) return "-";
  try {
    const dt = new Date(value);
    if (Number.isNaN(dt.getTime())) return value;
    return dt.toISOString().replace("T", " ").replace(".000Z", "Z");
  } catch {
    return value;
  }
}

function esc(text) {
  const s = String(text ?? "");
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function tag(text, cls) {
  return `<span class="tag ${cls}">${esc(text)}</span>`;
}

async function apiGet(path, useAdmin = true) {
  const resp = await fetch(`${getBaseUrl()}${path}`, {
    method: "GET",
    headers: useAdmin ? adminHeaders() : {},
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || data.ok === false) {
    throw new Error(data.error || data.message || `HTTP ${resp.status}`);
  }
  return data;
}

async function apiPost(path, payload, useAdmin = true) {
  const resp = await fetch(`${getBaseUrl()}${path}`, {
    method: "POST",
    headers: useAdmin ? adminHeaders() : { "Content-Type": "application/json" },
    body: JSON.stringify(payload || {}),
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || data.ok === false) {
    throw new Error(data.error || data.message || `HTTP ${resp.status}`);
  }
  return data;
}

async function testConnection() {
  try {
    const data = await apiGet("/api/health", false);
    $("healthDot").className = "dot dot-on";
    $("healthText").textContent = `Connected (${data.time_utc || "ok"})`;
    toast("Connection OK");
  } catch (err) {
    $("healthDot").className = "dot dot-off";
    $("healthText").textContent = `Error: ${err.message}`;
    toast(`Connection failed: ${err.message}`);
  }
}

function fillFormFromLicense(lic) {
  $("fToken").value = lic.token || "";
  $("fCustomer").value = lic.customer_name || "";
  $("fExpiresAt").value = (lic.expires_at || "").replace("T", " ").replace("Z", "");
  $("fLogins").value = (lic.allowed_logins || []).join(",");
  $("fServers").value = (lic.allowed_servers || []).join(",");
  $("fNotes").value = lic.notes || "";
  $("fActive").checked = !!lic.active;
  $("fRevoked").checked = !!lic.revoked;
}

function clearForm() {
  $("fToken").value = "";
  $("fCustomer").value = "";
  $("fExpiresAt").value = "";
  $("fLogins").value = "";
  $("fServers").value = "";
  $("fNotes").value = "";
  $("fActive").checked = true;
  $("fRevoked").checked = false;
}

function licenseStatusCell(lic) {
  const now = Date.now();
  const exp = Date.parse(lic.expires_at || "");
  if (lic.revoked) return tag("REVOKED", "tag-bad");
  if (!lic.active) return tag("DISABLED", "tag-warn");
  if (!Number.isNaN(exp) && exp < now) return tag("EXPIRED", "tag-bad");
  return tag("VALID", "tag-ok");
}

function renderLicenses() {
  const body = $("licensesBody");
  if (!state.licenses.length) {
    body.innerHTML = `<tr><td colspan="8">No licenses found.</td></tr>`;
    return;
  }

  body.innerHTML = state.licenses.map((lic) => {
    return `
      <tr>
        <td><code>${esc(lic.token)}</code></td>
        <td>${esc(lic.customer_name)}</td>
        <td>${licenseStatusCell(lic)}</td>
        <td>${esc(formatDate(lic.expires_at))}</td>
        <td>${esc((lic.allowed_logins || []).join(", ")) || "-"}</td>
        <td>${esc((lic.allowed_servers || []).join(", ")) || "-"}</td>
        <td>${esc(formatDate(lic.last_seen_at))}</td>
        <td>
          <div class="row wrap">
            <button class="btn" data-action="edit" data-token="${esc(lic.token)}">Edit</button>
            <button class="btn btn-warning" data-action="extend30" data-token="${esc(lic.token)}">+30d</button>
            <button class="btn ${lic.revoked ? "" : "btn-danger"}" data-action="toggleRevoke" data-token="${esc(lic.token)}" data-revoked="${lic.revoked ? "1" : "0"}">
              ${lic.revoked ? "Unrevoke" : "Revoke"}
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join("");
}

function renderEvents() {
  const body = $("eventsBody");
  if (!state.events.length) {
    body.innerHTML = `<tr><td colspan="9">No events found.</td></tr>`;
    return;
  }
  body.innerHTML = state.events.map((ev) => {
    const st = ev.allowed ? tag(ev.status || "VALID", "tag-ok") : tag(ev.status || "DENIED", "tag-bad");
    return `
      <tr>
        <td>${esc(formatDate(ev.event_time))}</td>
        <td><code>${esc(ev.token)}</code></td>
        <td>${st}</td>
        <td>${esc(ev.message || "-")}</td>
        <td>${esc(ev.login || "-")}</td>
        <td>${esc(ev.server || "-")}</td>
        <td>${esc(ev.program || "-")}</td>
        <td>${esc(ev.build || "-")}</td>
        <td>${esc(ev.remote_ip || "-")}</td>
      </tr>
    `;
  }).join("");
}

function renderStats() {
  const total = state.licenses.length;
  const now = Date.now();
  let active = 0;
  let revoked = 0;
  let expiring7d = 0;
  for (const lic of state.licenses) {
    if (lic.revoked) revoked += 1;
    if (lic.active && !lic.revoked) active += 1;
    const exp = Date.parse(lic.expires_at || "");
    if (!Number.isNaN(exp)) {
      const diff = exp - now;
      if (diff >= 0 && diff <= 7 * 24 * 60 * 60 * 1000) expiring7d += 1;
    }
  }
  const denied = state.events.filter((e) => !e.allowed).length;
  $("statTotalLicenses").textContent = String(total);
  $("statActive").textContent = String(active);
  $("statRevoked").textContent = String(revoked);
  $("statExpiring7d").textContent = String(expiring7d);
  $("statEvents").textContent = String(state.events.length);
  $("statDenied").textContent = String(denied);
}

async function loadLicenses() {
  const token = $("licenseFilterToken").value.trim();
  const limit = Number($("licenseLimit").value || 200);
  const query = new URLSearchParams();
  query.set("limit", String(limit));
  query.set("offset", "0");
  if (token) query.set("token", token);
  const data = await apiGet(`/api/v1/admin/licenses?${query.toString()}`);
  state.licenses = data.items || [];
  renderLicenses();
  renderStats();
  toast(`Loaded ${state.licenses.length} licenses`);
}

async function loadEvents() {
  const token = $("eventsFilterToken").value.trim();
  const limit = Number($("eventsLimit").value || 200);
  const query = new URLSearchParams();
  query.set("limit", String(limit));
  query.set("offset", "0");
  if (token) query.set("token", token);
  const data = await apiGet(`/api/v1/admin/events?${query.toString()}`);
  state.events = data.items || [];
  renderEvents();
  renderStats();
  toast(`Loaded ${state.events.length} events`);
}

async function saveLicense() {
  const payload = {
    token: $("fToken").value.trim(),
    customer_name: $("fCustomer").value.trim(),
    expires_at: $("fExpiresAt").value.trim(),
    allowed_logins: $("fLogins").value.trim(),
    allowed_servers: $("fServers").value.trim(),
    notes: $("fNotes").value.trim(),
    active: $("fActive").checked,
    revoked: $("fRevoked").checked,
  };
  if (!payload.token || !payload.expires_at) {
    throw new Error("Token and Expires At are required");
  }
  await apiPost("/api/v1/admin/license/upsert", payload);
  toast(`License saved: ${payload.token}`);
  await loadLicenses();
}

async function toggleRevoke(token, currentlyRevoked) {
  await apiPost("/api/v1/admin/license/revoke", {
    token,
    revoked: !currentlyRevoked,
  });
  toast(`License updated: ${token}`);
  await loadLicenses();
}

async function extendLicense(token, days = 30) {
  await apiPost("/api/v1/admin/license/extend", { token, days });
  toast(`License extended: ${token} (+${days}d)`);
  await loadLicenses();
}

async function runValidate() {
  const payload = {
    token: $("vToken").value.trim(),
    login: $("vLogin").value.trim(),
    server: $("vServer").value.trim(),
    company: $("vCompany").value.trim(),
    name: $("vName").value.trim(),
    program: $("vProgram").value.trim(),
    build: $("vBuild").value.trim(),
  };
  const result = await apiPost("/api/v1/license/validate", payload, false);
  $("validateOutput").textContent = JSON.stringify(result, null, 2);
  toast(`Validate: ${result.status || "done"}`);
}

async function refreshAll() {
  await testConnection();
  await loadLicenses();
  await loadEvents();
}

function bindEvents() {
  $("saveConnBtn").addEventListener("click", () => {
    localStorage.setItem("insidebot_admin_base_url", getBaseUrl());
    localStorage.setItem("insidebot_admin_key", getAdminKey());
    toast("Connection settings saved");
  });
  $("testConnBtn").addEventListener("click", async () => {
    try {
      await testConnection();
    } catch (err) {
      toast(err.message);
    }
  });
  $("refreshAllBtn").addEventListener("click", async () => {
    try {
      await refreshAll();
    } catch (err) {
      toast(err.message);
    }
  });

  $("refreshLicensesBtn").addEventListener("click", async () => {
    try {
      await loadLicenses();
    } catch (err) {
      toast(err.message);
    }
  });
  $("refreshEventsBtn").addEventListener("click", async () => {
    try {
      await loadEvents();
    } catch (err) {
      toast(err.message);
    }
  });

  $("upsertBtn").addEventListener("click", async () => {
    try {
      await saveLicense();
    } catch (err) {
      toast(err.message);
    }
  });
  $("clearFormBtn").addEventListener("click", clearForm);

  $("validateBtn").addEventListener("click", async () => {
    try {
      await runValidate();
    } catch (err) {
      toast(err.message);
      $("validateOutput").textContent = JSON.stringify({ error: err.message }, null, 2);
    }
  });

  $("licensesBody").addEventListener("click", async (ev) => {
    const btn = ev.target.closest("button[data-action]");
    if (!btn) return;
    const action = btn.getAttribute("data-action");
    const token = btn.getAttribute("data-token");
    const revoked = btn.getAttribute("data-revoked") === "1";

    try {
      if (action === "edit") {
        const lic = state.licenses.find((x) => x.token === token);
        if (lic) fillFormFromLicense(lic);
      } else if (action === "toggleRevoke") {
        await toggleRevoke(token, revoked);
      } else if (action === "extend30") {
        await extendLicense(token, 30);
      }
    } catch (err) {
      toast(err.message);
    }
  });
}

function loadSavedConnection() {
  $("baseUrl").value = localStorage.getItem("insidebot_admin_base_url") || window.location.origin;
  $("adminKey").value = localStorage.getItem("insidebot_admin_key") || "";
}

async function init() {
  loadSavedConnection();
  bindEvents();
  await testConnection();
  if (getAdminKey()) {
    try {
      await loadLicenses();
      await loadEvents();
    } catch (err) {
      toast(err.message);
    }
  } else {
    renderLicenses();
    renderEvents();
    renderStats();
  }
}

init();
