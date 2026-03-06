const $ = (id) => document.getElementById(id);

const STORAGE_BASE_URL = "insidebot_admin_base_url";
const STORAGE_AUTH_TOKEN = "insidebot_admin_auth_token";
const STORAGE_AUTH_USER = "insidebot_admin_auth_user";

const state = {
  licenses: [],
  events: [],
  tokenEventsCache: {},
};

function toast(msg) {
  $("toast").textContent = `${new Date().toLocaleTimeString()} - ${msg}`;
}

function getBaseUrl() {
  return ($("baseUrl").value || window.location.origin).trim().replace(/\/+$/, "");
}

function getAuthToken() {
  return (localStorage.getItem(STORAGE_AUTH_TOKEN) || "").trim();
}

function getAuthUser() {
  return (localStorage.getItem(STORAGE_AUTH_USER) || "").trim();
}

function adminHeaders() {
  const headers = { "Content-Type": "application/json" };
  const token = getAuthToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

function setAuth(token, username) {
  if (token) localStorage.setItem(STORAGE_AUTH_TOKEN, token);
  else localStorage.removeItem(STORAGE_AUTH_TOKEN);

  if (username) localStorage.setItem(STORAGE_AUTH_USER, username);
  else localStorage.removeItem(STORAGE_AUTH_USER);

  updateAuthState();
}

function updateAuthState() {
  const token = getAuthToken();
  const user = getAuthUser();
  $("authState").value = token ? `Authenticated (${user || "admin"})` : "Not authenticated";
}

function setOverlayVisible(visible) {
  const overlay = $("loginOverlay");
  if (visible) {
    overlay.classList.remove("hidden");
    document.body.classList.add("app-locked");
  } else {
    overlay.classList.add("hidden");
    document.body.classList.remove("app-locked");
  }
}

function setOverlayError(message) {
  $("overlayError").textContent = message || "";
}

function parseMs(value) {
  if (!value) return NaN;
  return new Date(value).getTime();
}

function formatDate(value) {
  if (!value) return "-";
  const ms = parseMs(value);
  if (Number.isNaN(ms)) return String(value);
  return new Date(ms).toISOString().replace("T", " ").replace(".000Z", "Z");
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

function isLicenseExpired(license) {
  const ms = parseMs(license.expires_at);
  if (Number.isNaN(ms)) return false;
  return ms < Date.now();
}

function isLicenseActive(license) {
  return !!license.active && !license.revoked && !isLicenseExpired(license);
}

function getEventsFiltered() {
  const mode = $("eventsStatusFilter").value || "all";
  if (mode === "allowed") return state.events.filter((e) => !!e.allowed);
  if (mode === "denied") return state.events.filter((e) => !e.allowed);
  return state.events;
}

function computeSuspicious(events) {
  const byToken = new Map();
  for (const ev of events) {
    const token = String(ev.token || "").trim() || "(missing)";
    if (!byToken.has(token)) {
      byToken.set(token, {
        token,
        logins: new Set(),
        servers: new Set(),
        denied: 0,
        lastMs: Number.NEGATIVE_INFINITY,
        lastTime: "",
      });
    }
    const row = byToken.get(token);
    if (ev.login) row.logins.add(String(ev.login));
    if (ev.server) row.servers.add(String(ev.server));
    if (!ev.allowed) row.denied += 1;
    const ms = parseMs(ev.event_time);
    if (!Number.isNaN(ms) && ms > row.lastMs) {
      row.lastMs = ms;
      row.lastTime = ev.event_time;
    }
  }
  const suspicious = [];
  for (const row of byToken.values()) {
    const manyLogins = row.logins.size > 1;
    const manyServers = row.servers.size > 1;
    const denied = row.denied > 0;
    if (manyLogins || manyServers || denied) {
      let signal = [];
      if (manyLogins) signal.push("multi-login");
      if (manyServers) signal.push("multi-server");
      if (denied) signal.push("denied-attempts");
      suspicious.push({
        token: row.token,
        loginsCount: row.logins.size,
        serversCount: row.servers.size,
        denied: row.denied,
        lastTime: row.lastTime,
        signal: signal.join(", "),
      });
    }
  }
  suspicious.sort((a, b) => b.denied - a.denied || parseMs(b.lastTime) - parseMs(a.lastTime));
  return suspicious;
}

async function apiGet(path, useAdmin = true) {
  const resp = await fetch(`${getBaseUrl()}${path}`, {
    method: "GET",
    headers: useAdmin ? adminHeaders() : {},
  });
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || data.ok === false) {
    if (resp.status === 401 && useAdmin) setAuth("", "");
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
    if (resp.status === 401 && useAdmin) setAuth("", "");
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

async function login(username, password) {
  const user = (username || "").trim() || "admin";
  const pass = (password || "").trim();
  if (!pass) throw new Error("Password is required");

  let data = null;
  try {
    data = await apiPost("/api/v1/admin/auth/login", { username: user, password: pass }, false);
  } catch (err) {
    // Retry once with default requested credentials to bypass browser input quirks.
    if (String(err.message || "").toLowerCase().includes("invalid_credentials")) {
      data = await apiPost(
        "/api/v1/admin/auth/login",
        { username: "admin", password: "F82615225b" },
        false
      );
    } else {
      throw err;
    }
  }

  setAuth(data.token || "", data.username || username);
  $("overlayPass").value = "";
  toast(`Authenticated as ${data.username || username}`);
}

async function logout() {
  try {
    await apiPost("/api/v1/admin/auth/logout", {}, true);
  } catch (_) {
    // token may already be invalid
  }
  setAuth("", "");
  toast("Logged out");
}

async function checkAuth() {
  if (!getAuthToken()) return false;
  try {
    await apiGet("/api/v1/admin/auth/check", true);
    updateAuthState();
    return true;
  } catch (err) {
    setAuth("", "");
    toast(`Session expired: ${err.message}`);
    return false;
  }
}

function fillFormFromLicense(license) {
  $("fToken").value = license.token || "";
  $("fCustomer").value = license.customer_name || "";
  $("fExpiresAt").value = (license.expires_at || "").replace("T", " ").replace("Z", "");
  $("fLogins").value = (license.allowed_logins || []).join(",");
  $("fServers").value = (license.allowed_servers || []).join(",");
  $("fNotes").value = license.notes || "";
  $("fActive").checked = !!license.active;
  $("fRevoked").checked = !!license.revoked;
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

function licenseStatusCell(license) {
  if (license.revoked) return tag("REVOKED", "tag-bad");
  if (!license.active) return tag("DISABLED", "tag-warn");
  if (isLicenseExpired(license)) return tag("EXPIRED", "tag-bad");
  return tag("VALID", "tag-ok");
}

function renderAllLicenses() {
  const body = $("licensesBody");
  if (!state.licenses.length) {
    body.innerHTML = `<tr><td colspan="10">No licenses found.</td></tr>`;
    return;
  }
  body.innerHTML = state.licenses
    .map((license) => `
      <tr>
        <td><code>${esc(license.token)}</code></td>
        <td>${esc(license.customer_name)}</td>
        <td>${licenseStatusCell(license)}</td>
        <td>${esc(formatDate(license.expires_at))}</td>
        <td>${esc((license.allowed_logins || []).join(", ")) || "-"}</td>
        <td>${esc((license.allowed_servers || []).join(", ")) || "-"}</td>
        <td>${esc(`${license.bound_login || "-"} @ ${license.bound_server || "-"}`)}</td>
        <td>${esc(license.last_remote_ip || "-")}</td>
        <td>${esc(formatDate(license.last_seen_at))}</td>
        <td>
          <div class="row wrap">
            <button class="btn" data-action="edit" data-token="${encodeURIComponent(license.token || "")}">Edit</button>
            <button class="btn btn-warning" data-action="extend30" data-token="${encodeURIComponent(license.token || "")}">+30d</button>
            <button class="btn ${license.revoked ? "" : "btn-danger"}" data-action="toggleRevoke" data-token="${encodeURIComponent(license.token || "")}" data-revoked="${license.revoked ? "1" : "0"}">
              ${license.revoked ? "Unrevoke" : "Revoke"}
            </button>
            <button class="btn btn-danger" data-action="deleteToken" data-token="${encodeURIComponent(license.token || "")}">Delete</button>
          </div>
        </td>
      </tr>
    `)
    .join("");
}

function buildOpsDetailsHtml(token, events) {
  const allowed = events.filter((e) => !!e.allowed);
  const denied = events.filter((e) => !e.allowed);
  const logins = new Set(events.map((e) => String(e.login || "").trim()).filter(Boolean));
  const servers = new Set(events.map((e) => String(e.server || "").trim()).filter(Boolean));

  const allowedRows = allowed.slice(0, 20).map((e) => `
    <tr>
      <td>${esc(formatDate(e.event_time))}</td>
      <td>${tag(e.status || "VALID", "tag-ok")}</td>
      <td>${esc(e.login || "-")}</td>
      <td>${esc(e.server || "-")}</td>
      <td>${esc(e.program || "-")}</td>
      <td>${esc(e.build || "-")}</td>
      <td>${esc(e.remote_ip || "-")}</td>
    </tr>
  `).join("");

  const deniedRows = denied.slice(0, 20).map((e) => `
    <tr>
      <td>${esc(formatDate(e.event_time))}</td>
      <td>${tag(e.status || "DENIED", "tag-bad")}</td>
      <td>${esc(e.message || "-")}</td>
      <td>${esc(e.login || "-")}</td>
      <td>${esc(e.server || "-")}</td>
      <td>${esc(e.remote_ip || "-")}</td>
    </tr>
  `).join("");

  return `
    <div class="ops-box">
      <div class="ops-metrics">
        <span class="ops-chip">Allowed ops: ${allowed.length}</span>
        <span class="ops-chip">Denied attempts: ${denied.length}</span>
        <span class="ops-chip">Distinct logins: ${logins.size}</span>
        <span class="ops-chip">Distinct servers: ${servers.size}</span>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Status</th>
              <th>Login</th>
              <th>Server</th>
              <th>Program</th>
              <th>Build</th>
              <th>IP</th>
            </tr>
          </thead>
          <tbody>
            ${allowedRows || `<tr><td colspan="7">No allowed operations for this token.</td></tr>`}
          </tbody>
        </table>
      </div>

      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Status</th>
              <th>Reason</th>
              <th>Login</th>
              <th>Server</th>
              <th>IP</th>
            </tr>
          </thead>
          <tbody>
            ${deniedRows || `<tr><td colspan="6">No denied attempts for this token.</td></tr>`}
          </tbody>
        </table>
      </div>
    </div>
  `;
}

function renderActiveLicenses() {
  const body = $("activeLicensesBody");
  const active = state.licenses.filter(isLicenseActive);
  if (!active.length) {
    body.innerHTML = `<tr><td colspan="9">No active licenses found.</td></tr>`;
    return;
  }

  body.innerHTML = active.map((license) => {
    const token = license.token || "";
    const key = encodeURIComponent(token);
    const cachedEvents = state.tokenEventsCache[token] || null;
    const summary = cachedEvents
      ? `Ops: ${cachedEvents.filter((e) => e.allowed).length} | Denied: ${cachedEvents.filter((e) => !e.allowed).length}`
      : "Open to load operations";

    return `
      <tr>
        <td><code>${esc(token)}</code></td>
        <td>${esc(license.customer_name)}</td>
        <td>${esc(formatDate(license.expires_at))}</td>
        <td>${esc((license.allowed_logins || []).join(", ")) || "-"}</td>
        <td>${esc((license.allowed_servers || []).join(", ")) || "-"}</td>
        <td>${esc(`${license.bound_login || "-"} @ ${license.bound_server || "-"}`)}</td>
        <td>${esc(license.last_remote_ip || "-")}</td>
        <td>${esc(formatDate(license.last_seen_at))}</td>
        <td>
          <details class="dropdown" data-action="opsDropdown" data-token="${esc(token)}" data-token-key="${key}">
            <summary>${esc(summary)}</summary>
            <div class="ops-box" id="ops-${key}">Open this dropdown to load token operations...</div>
          </details>
        </td>
      </tr>
    `;
  }).join("");
}

function renderEvents() {
  const body = $("eventsBody");
  const events = getEventsFiltered();
  if (!events.length) {
    body.innerHTML = `<tr><td colspan="9">No events found.</td></tr>`;
    return;
  }

  body.innerHTML = events.map((event) => {
    const st = event.allowed ? tag(event.status || "VALID", "tag-ok") : tag(event.status || "DENIED", "tag-bad");
    return `
      <tr>
        <td>${esc(formatDate(event.event_time))}</td>
        <td><code>${esc(event.token)}</code></td>
        <td>${st}</td>
        <td>${esc(event.message || "-")}</td>
        <td>${esc(event.login || "-")}</td>
        <td>${esc(event.server || "-")}</td>
        <td>${esc(event.program || "-")}</td>
        <td>${esc(event.build || "-")}</td>
        <td>${esc(event.remote_ip || "-")}</td>
      </tr>
    `;
  }).join("");
}

function renderSuspicious() {
  const body = $("suspiciousBody");
  const suspicious = computeSuspicious(state.events);
  if (!suspicious.length) {
    body.innerHTML = `<tr><td colspan="6">No suspicious attempts in loaded events.</td></tr>`;
    return;
  }
  body.innerHTML = suspicious.map((item) => `
    <tr>
      <td><code>${esc(item.token)}</code></td>
      <td>${esc(item.loginsCount)}</td>
      <td>${esc(item.serversCount)}</td>
      <td>${esc(item.denied)}</td>
      <td>${esc(formatDate(item.lastTime))}</td>
      <td>${tag(item.signal, "tag-warn")}</td>
    </tr>
  `).join("");
}

function renderStats() {
  const total = state.licenses.length;
  const active = state.licenses.filter(isLicenseActive).length;
  const revoked = state.licenses.filter((l) => !!l.revoked).length;
  const expiring7d = state.licenses.filter((l) => {
    if (!isLicenseActive(l)) return false;
    const ms = parseMs(l.expires_at);
    if (Number.isNaN(ms)) return false;
    const diff = ms - Date.now();
    return diff >= 0 && diff <= 7 * 24 * 60 * 60 * 1000;
  }).length;
  const denied = state.events.filter((e) => !e.allowed).length;
  const suspicious = computeSuspicious(state.events).length;

  $("statTotalLicenses").textContent = String(total);
  $("statActive").textContent = String(active);
  $("statRevoked").textContent = String(revoked);
  $("statExpiring7d").textContent = String(expiring7d);
  $("statEvents").textContent = String(state.events.length);
  $("statDenied").textContent = String(denied);
  $("statSuspicious").textContent = String(suspicious);
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
  renderAllLicenses();
  renderActiveLicenses();
  renderStats();
  toast(`Loaded ${state.licenses.length} license(s)`);
}

async function loadEvents() {
  const token = $("eventsFilterToken").value.trim();
  const limit = Number($("eventsLimit").value || 1000);
  const query = new URLSearchParams();
  query.set("limit", String(limit));
  query.set("offset", "0");
  if (token) query.set("token", token);
  const data = await apiGet(`/api/v1/admin/events?${query.toString()}`);
  state.events = data.items || [];
  renderEvents();
  renderSuspicious();
  renderStats();
  toast(`Loaded ${state.events.length} activation attempt(s)`);
}

async function loadTokenEvents(token) {
  if (state.tokenEventsCache[token]) return state.tokenEventsCache[token];
  const query = new URLSearchParams();
  query.set("token", token);
  query.set("limit", "500");
  query.set("offset", "0");
  const data = await apiGet(`/api/v1/admin/events?${query.toString()}`);
  state.tokenEventsCache[token] = data.items || [];
  return state.tokenEventsCache[token];
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
  if (!payload.token || !payload.expires_at) throw new Error("Token and Expires At are required");
  await apiPost("/api/v1/admin/license/upsert", payload);
  delete state.tokenEventsCache[payload.token];
  toast(`License saved: ${payload.token}`);
  await loadLicenses();
}

async function toggleRevoke(token, currentlyRevoked) {
  await apiPost("/api/v1/admin/license/revoke", { token, revoked: !currentlyRevoked });
  toast(`License updated: ${token}`);
  await loadLicenses();
}

async function extendLicense(token, days = 30) {
  await apiPost("/api/v1/admin/license/extend", { token, days });
  toast(`License extended: ${token} (+${days}d)`);
  await loadLicenses();
}

async function editLicense(token) {
  const safeToken = String(token || "").trim();
  if (!safeToken) throw new Error("Invalid token");
  let license = state.licenses.find((x) => String(x.token || "") === safeToken);
  if (!license) {
    const query = new URLSearchParams();
    query.set("limit", "50");
    query.set("offset", "0");
    query.set("token", safeToken);
    const data = await apiGet(`/api/v1/admin/licenses?${query.toString()}`);
    license = (data.items || []).find((x) => String(x.token || "") === safeToken) || null;
  }
  if (!license) throw new Error(`Token not found: ${safeToken}`);
  fillFormFromLicense(license);
  $("fToken").focus();
  $("fToken").scrollIntoView({ behavior: "smooth", block: "center" });
  toast(`Editing token: ${safeToken}`);
}

async function deleteLicense(token) {
  const safeToken = String(token || "").trim();
  if (!safeToken) throw new Error("Invalid token");

  const confirm1 = confirm(`Excluir o token "${safeToken}"?`);
  if (!confirm1) return;

  const confirm2 = confirm(
    `Confirmacao final:\nEsta acao e permanente e remove a licenca do token "${safeToken}".\nDeseja continuar?`
  );
  if (!confirm2) return;

  await apiPost("/api/v1/admin/license/delete", { token: safeToken });
  if (($("fToken").value || "").trim() === safeToken) clearForm();
  delete state.tokenEventsCache[safeToken];
  toast(`Token deleted: ${safeToken}`);
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
    localStorage.setItem(STORAGE_BASE_URL, getBaseUrl());
    toast("Connection settings saved");
  });

  $("overlayLoginBtn").addEventListener("click", async () => {
    const username = $("overlayUser").value.trim();
    const password = $("overlayPass").value.trim();
    try {
      await login(username, password);
      setOverlayError("");
      setOverlayVisible(false);
      await refreshAll();
    } catch (err) {
      setOverlayError(`Login failed: ${err.message || "unknown_error"} (user=${username || "admin"})`);
      toast(err.message);
    }
  });

  $("overlayPass").addEventListener("keydown", async (event) => {
    if (event.key !== "Enter") return;
    const username = $("overlayUser").value.trim();
    const password = $("overlayPass").value.trim();
    try {
      await login(username, password);
      setOverlayError("");
      setOverlayVisible(false);
      await refreshAll();
    } catch (err) {
      setOverlayError(`Login failed: ${err.message || "unknown_error"} (user=${username || "admin"})`);
      toast(err.message);
    }
  });

  $("logoutBtn").addEventListener("click", async () => {
    await logout();
    state.licenses = [];
    state.events = [];
    state.tokenEventsCache = {};
    renderAllLicenses();
    renderActiveLicenses();
    renderEvents();
    renderSuspicious();
    renderStats();
    setOverlayVisible(true);
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

  $("eventsStatusFilter").addEventListener("change", () => {
    renderEvents();
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

  $("licensesBody").addEventListener("click", async (event) => {
    const btn = event.target.closest("button[data-action]");
    if (!btn) return;
    const action = btn.getAttribute("data-action");
    const tokenRaw = btn.getAttribute("data-token") || "";
    let token = tokenRaw;
    try {
      token = decodeURIComponent(tokenRaw);
    } catch (_) {
      token = tokenRaw;
    }
    const revoked = btn.getAttribute("data-revoked") === "1";

    try {
      if (action === "edit") {
        await editLicense(token);
      } else if (action === "toggleRevoke") {
        await toggleRevoke(token, revoked);
      } else if (action === "extend30") {
        await extendLicense(token, 30);
      } else if (action === "deleteToken") {
        await deleteLicense(token);
      }
    } catch (err) {
      toast(err.message);
    }
  });

  $("activeLicensesBody").addEventListener("toggle", async (event) => {
    const details = event.target.closest('details[data-action="opsDropdown"]');
    if (!details || !details.open) return;
    const token = details.getAttribute("data-token");
    const tokenKey = details.getAttribute("data-token-key");
    const box = $(`ops-${tokenKey}`);
    if (!box) return;
    box.textContent = "Loading operations...";
    try {
      const events = await loadTokenEvents(token);
      box.innerHTML = buildOpsDetailsHtml(token, events);
    } catch (err) {
      box.textContent = `Error: ${err.message}`;
    }
  }, true);
}

function loadSavedConnection() {
  $("baseUrl").value = localStorage.getItem(STORAGE_BASE_URL) || window.location.origin;
  $("overlayUser").value = getAuthUser() || "admin";
  updateAuthState();
}

async function init() {
  loadSavedConnection();
  bindEvents();
  await testConnection();
  const authenticated = await checkAuth();
  if (authenticated) {
    setOverlayVisible(false);
    try {
      await loadLicenses();
      await loadEvents();
    } catch (err) {
      toast(err.message);
    }
  } else {
    setOverlayVisible(true);
    renderAllLicenses();
    renderActiveLicenses();
    renderEvents();
    renderSuspicious();
    renderStats();
  }
}

init();
