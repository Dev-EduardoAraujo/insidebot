const $ = (id) => document.getElementById(id);

const STORAGE_BASE_URL = "insidebot_admin_base_url";
const STORAGE_AUTH_TOKEN = "insidebot_admin_auth_token";
const STORAGE_AUTH_USER = "insidebot_admin_auth_user";

function setStatus(message) {
  $("statusText").textContent = message || "";
}

function setError(message) {
  $("errorText").textContent = message || "";
}

function currentOriginBaseUrl() {
  return window.location.origin.trim().replace(/\/+$/, "");
}

function normalizeCredential(value) {
  return String(value ?? "")
    .replace(/\uFEFF/g, "")
    .replace(/[\u200B-\u200D\u2060]/g, "")
    .trim();
}

function getBaseUrl() {
  return currentOriginBaseUrl();
}

function saveBaseUrl() {
  localStorage.setItem(STORAGE_BASE_URL, currentOriginBaseUrl());
}

function getToken() {
  return (localStorage.getItem(STORAGE_AUTH_TOKEN) || "").trim();
}

function setAuth(token, username) {
  if (token) {
    localStorage.setItem(STORAGE_AUTH_TOKEN, token);
  } else {
    localStorage.removeItem(STORAGE_AUTH_TOKEN);
  }
  if (username) {
    localStorage.setItem(STORAGE_AUTH_USER, username);
  } else {
    localStorage.removeItem(STORAGE_AUTH_USER);
  }
}

async function fetchJson(path, options = {}) {
  const fetchOptions = { credentials: "same-origin", ...options };
  const resp = await fetch(`${getBaseUrl()}${path}`, fetchOptions);
  const data = await resp.json().catch(() => ({}));
  if (!resp.ok || data.ok === false) {
    throw new Error(data.error || data.message || `HTTP ${resp.status}`);
  }
  return data;
}

async function checkExistingSession() {
  const token = getToken();
  const headers = token ? { Authorization: `Bearer ${token}` } : {};
  try {
    await fetchJson("/api/v1/admin/auth/check", {
      method: "GET",
      headers,
    });
    window.location.replace("/admin");
    return true;
  } catch (_) {
    if (token) setAuth("", "");
    return false;
  }
}

async function testConnection() {
  setError("");
  setStatus("Testing connection...");
  try {
    const data = await fetchJson("/api/health", { method: "GET" });
    setStatus(`Connected (${data.time_utc || "ok"})`);
  } catch (err) {
    setStatus("");
    setError(`Connection failed: ${err.message}`);
  }
}

async function authLogin(username, password) {
  try {
    return await fetchJson("/api/v1/admin/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
  } catch (err) {
    const msg = String(err?.message || "").toLowerCase();
    if (!msg.includes("invalid_credentials")) {
      throw err;
    }
  }

  const form = new URLSearchParams();
  form.set("username", username);
  form.set("password", password);
  return await fetchJson("/api/v1/admin/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
}

async function doLogin() {
  const username = normalizeCredential($("username").value || "") || "admin";
  const password = normalizeCredential($("password").value || "");
  if (!password) {
    setError("Password is required.");
    return;
  }

  saveBaseUrl();
  setError("");
  setStatus("Authenticating...");

  try {
    const data = await authLogin(username, password);
    setAuth(data.token || "", data.username || username);
    window.location.replace("/admin");
  } catch (err) {
    setStatus("");
    setError(`Login failed: ${err.message}`);
  }
}

function explainReason() {
  const reason = new URLSearchParams(window.location.search).get("reason") || "";
  if (reason === "session_expired") {
    setStatus("Your session expired. Please login again.");
  } else if (reason === "logged_out") {
    setStatus("You have been logged out.");
  } else if (reason === "missing_session") {
    setStatus("Please login to continue.");
  }
}

function bindEvents() {
  $("loginBtn").addEventListener("click", doLogin);
  $("testConnBtn").addEventListener("click", testConnection);
  $("password").addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      doLogin();
    }
  });
}

async function init() {
  const origin = currentOriginBaseUrl();
  localStorage.setItem(STORAGE_BASE_URL, origin);
  $("baseUrl").value = origin;
  $("baseUrl").setAttribute("readonly", "readonly");
  $("username").value = localStorage.getItem(STORAGE_AUTH_USER) || "admin";
  bindEvents();
  explainReason();
  await checkExistingSession();
}

init();
