// Klien kecil untuk Neon Auth (Better Auth) + Neon Data API (PostgREST),
// tanpa build step. Mengikuti alur yang sama dengan @neondatabase/neon-js:
// sesi via cookie / bearer token, JWT dari header `set-auth-jwt` atau /token.
import { AUTH_URL, API_URL } from '../config.js';

const SESSION_KEY = 'tempuh.session';
let jwtCache = null; // { token, exp }

function store(key, value) {
  try {
    if (value == null) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch (_) {}
}
function load(key) {
  try { return localStorage.getItem(key); } catch (_) { return null; }
}

function decodeExp(jwt) {
  try {
    const payload = JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return payload.exp || 0;
  } catch (_) {
    return 0;
  }
}

function remember(jwt) {
  if (jwt) jwtCache = { token: jwt, exp: decodeExp(jwt) };
}

export class ApiError extends Error {
  constructor(message, status, body) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

async function authFetch(path, { method = 'GET', body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const session = load(SESSION_KEY);
  if (session) headers.Authorization = `Bearer ${session}`;
  const res = await fetch(AUTH_URL + path, {
    method,
    headers,
    credentials: 'include',
    body: body ? JSON.stringify(body) : undefined,
  });
  const bearer = res.headers.get('set-auth-token');
  if (bearer) store(SESSION_KEY, bearer);
  remember(res.headers.get('set-auth-jwt'));
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
  if (!res.ok) {
    const msg = (data && (data.message || data.error)) || `HTTP ${res.status}`;
    throw new ApiError(msg, res.status, data);
  }
  return data;
}

function rememberSession(data) {
  if (data && typeof data.token === 'string') store(SESSION_KEY, data.token);
  if (data && data.session && data.session.token && data.session.token.split('.').length === 3) {
    remember(data.session.token);
  }
}

export async function signIn(email, password) {
  const data = await authFetch('/sign-in/email', { method: 'POST', body: { email, password } });
  rememberSession(data);
  return data?.user ?? null;
}

export async function signUp(name, email, password) {
  const data = await authFetch('/sign-up/email', { method: 'POST', body: { name, email, password } });
  rememberSession(data);
  return data?.user ?? null;
}

export async function signOut() {
  try { await authFetch('/sign-out', { method: 'POST', body: {} }); } catch (_) {}
  store(SESSION_KEY, null);
  jwtCache = null;
}

/** Pengguna yang sedang login, atau null. */
export async function currentUser() {
  try {
    const data = await authFetch('/get-session');
    if (!data || !data.user) return null;
    return data.user;
  } catch (_) {
    return null;
  }
}

async function getJwt() {
  const now = Date.now() / 1000;
  if (jwtCache && jwtCache.exp - 60 > now) return jwtCache.token;
  await authFetch('/get-session');
  if (jwtCache && jwtCache.exp - 60 > now) return jwtCache.token;
  const data = await authFetch('/token');
  remember(data && data.token);
  if (!jwtCache) throw new ApiError('Sesi berakhir, silakan login lagi.', 401);
  return jwtCache.token;
}

/**
 * Permintaan ke Data API. `path` contoh: '/activities?select=*'.
 * `prefer` diteruskan ke header Prefer PostgREST.
 */
export async function api(path, { method = 'GET', body, prefer } = {}) {
  const jwt = await getJwt();
  const headers = { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' };
  if (prefer) headers.Prefer = prefer;
  const res = await fetch(API_URL + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }
  if (!res.ok) {
    const msg = (data && (data.message || data.hint)) || `HTTP ${res.status}`;
    throw new ApiError(msg, res.status, data);
  }
  return data;
}
