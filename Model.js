// Model.js — DNS Changer data layer.
//
// Pure JS (no QML imports) so BarWidget.qml and Panel.qml can both
// `import "Model.js" as Model`.
//
// This ports github.com/DnsChanger/dnschanger-cli's Server interface,
// bundled server catalog, and connect/disconnect/status semantics:
//   - src/shared/interfaces/server.interface.ts -> Server shape (key, name,
//     servers[], rate, tags[])
//   - src/shared/validators/dns.validator.ts    -> isValidDnsAddress
//   - src/platforms/linux/linux.platform.ts     -> DEFAULT_DNS (clearDns)
//   - src/commands/connect.ts                    -> custom-server shape,
//     name/address lookup
//   - src/commands/status.ts                     -> connected / unknown /
//     disconnected semantics

var HOME = (function () {
  try { if (typeof Quickshell !== "undefined" && Quickshell.env) return Quickshell.env("HOME") } catch (e) {}
  try { if (typeof process !== "undefined" && process.env && process.env.HOME) return process.env.HOME } catch (e) {}
  return "~"
})()
var CACHE_DIR = HOME + "/.cache/omarchy-dns-changer"
var SERVERS_CACHE_FILE = CACHE_DIR + "/servers.json"
var STATE_FILE = CACHE_DIR + "/state.json"

// clearDns() on Linux sets exactly these four addresses (linux.platform.ts).
var DEFAULT_DNS = ["1.1.1.1", "8.8.8.8", "192.168.1.1", "127.0.0.1"]

// Bundled catalog: a snapshot of servers_DB.json (the same store the CLI
// fetches from github.com/DnsChanger/dnsChanger-desktop) so the picker works
// offline and on first launch, before scripts/dns-changer fetch-servers
// lands a fresher copy. Sorted by rate desc, same as fetchServersList().
var BUNDLED_SERVERS = [
  { key: "SHECAN", name: "Shecan", servers: ["178.22.122.100", "185.51.200.2"], rate: 10, tags: ["Iran", "Gaming", "Web", "Ai"] },
  { key: "zeusdns", name: "Zeus DNS", servers: ["37.32.5.60", "37.32.5.61"], rate: 8, tags: ["Iran", "Gaming", "Web", "Ai"] },
  { key: "ELECTRO", name: "Electro Team", servers: ["78.157.42.100", "78.157.42.101"], rate: 8, tags: ["Iran", "Gaming", "Web", "Ai", "Fivem"] },
  { key: "ASIA_TECH", name: "Asiatech", servers: ["194.36.174.161", "178.22.122.100"], rate: 6, tags: ["Iran", "Web"] },
  { key: "HiveDns", name: "Hive DNS", servers: ["87.107.52.11", "87.107.52.13"], rate: 6, tags: ["Web", "Gaming", "Developing", "Spotify"] },
  { key: "US_Dyn", name: "DynX Adblocker", servers: ["216.146.35.35", "216.146.36.36"], rate: 5, tags: ["Gaming"] },
  { key: " DynX_Iran_Anti-Sanctions", name: "DynX Iran Anti-Sanctions", servers: ["10.70.95.150", "10.70.95.162"], rate: 5, tags: ["Gaming", "Ad Blocker"] },
  { key: "GOOGLE", name: "Google", servers: ["8.8.8.8", "8.8.4.4"], rate: 5, tags: ["Gaming", "Web"] },
  { key: "RADAR_GAME", name: "Radar game", servers: ["10.202.10.10", "10.202.10.11"], rate: 4, tags: ["Iran", "Gaming", "Fivem"] },
  { key: "Shatel", name: "Shatel", servers: ["129.250.35.250", "129.250.35.251"], rate: 4, tags: ["Iran", "Gaming", "Web"] },
  { key: "Irancell", name: "Irancell", servers: ["74.82.42.42", "0.0.0.0"], rate: 4, tags: ["Iran", "Gaming", "Web"] },
  { key: "RapidGame", name: "RapidGame DNS", servers: ["94.182.137.166", "94.183.170.141"], rate: 4, tags: ["Gaming"] },
  { key: "MegaLan", name: "MegaLan", servers: ["95.111.55.251", "95.111.55.250"], rate: 3, tags: ["Gaming"] },
  { key: "ClOUD_FLARE", name: "Cloudflare", servers: ["1.1.1.1", "1.0.0.1"], rate: 3, tags: ["Web"] },
  { key: "AdGuard", name: "AdGuard[RU]", servers: ["94.140.14.14", "94.140.15.15"], rate: 3, tags: ["Web"] },
  { key: "OPENDNS", name: "OpenDNS", servers: ["208.67.222.222", "208.67.220.220"], rate: 2, tags: ["Web"] },
  { key: "QUAD9", name: "Quad9", servers: ["9.9.9.9", "149.112.112.112"], rate: 2, tags: ["Web"] },
  { key: "CleanBrowsing_Adult_Filter", name: "CleanBrowsing Adult Filter", servers: ["185.228.168.10", "185.228.169.11"], rate: 2, tags: ["Web"] },
  { key: "Fivem_1", name: "Fivem_1", servers: ["78.157.42.100", "69.96.69.96"], rate: 2, tags: ["Fivem"] },
  { key: "Fivem_2", name: "Fivem_2", servers: ["65.109.161.81", "78.157.42.101"], rate: 1, tags: ["Fivem"] },
  { key: "Fivem_3", name: "Fivem_3", servers: ["78.157.42.100", "10.0.0.0"], rate: 1, tags: ["Fivem"] },
  { key: "COMODO", name: "Comodo Secure DNS", servers: ["8.26.56.26", "8.20.247.20"], rate: 0, tags: ["Web"] },
  { key: "NOROTON", name: "Norton ConnectSafe", servers: ["199.85.126.10", "199.85.127.10"], rate: 0, tags: ["Web"] },
  { key: "YANDEX", name: "Yandex.DNS", servers: ["77.88.8.8", "77.88.8.1"], rate: 0, tags: ["Web"] },
  { key: "LEVEL3", name: "Level 3 DNS", servers: ["209.244.0.3", "209.244.0.4"], rate: 0, tags: ["Web"] },
  { key: "ULTRADNS", name: "UltraDNS", servers: ["156.154.70.1", "156.154.71.1"], rate: 0, tags: ["Web"] },
  { key: "DNSWATCH", name: "DNS.WATCH", servers: ["84.200.69.80", "84.200.70.40"], rate: 0, tags: ["Web"] },
  { key: "ControlD-Ads", name: "ControlD Ads", servers: ["76.76.2.2", "76.76.10.2"], rate: 0, tags: ["Ads"] },
  { key: "dns0.eu", name: "dns0.eu", servers: ["193.110.81.0", "185.253.5.0"], rate: 0, tags: ["Web"] }
]

// Official domain for servers whose provider is a well-known service with a
// recognizable public site — used to show a real favicon instead of a
// generated badge. The actual fetch (and rejecting DuckDuckGo's generic
// placeholder for a domain with no real icon — see scripts/dns-changer's
// header comment) happens in scripts/dns-changer favicons, not here. Not
// part of the CLI's Server interface; keyed by catalog `key` so it survives
// a live fetch-servers refresh (whose payload has no domain field) via
// attachDomains(). Deliberately does NOT cover the regional/gaming/niche
// entries with no identifiable official site (Zeus DNS, Electro Team,
// Fivem_*, ...) — those keep the generated badge unconditionally.
var DOMAIN_BY_KEY = {
  ClOUD_FLARE: "cloudflare.com",
  GOOGLE: "google.com",
  QUAD9: "quad9.net",
  OPENDNS: "opendns.com",
  YANDEX: "yandex.com",
  AdGuard: "adguard.com",
  COMODO: "comodo.com",
  NOROTON: "norton.com",
  LEVEL3: "level3.com",
  ULTRADNS: "ultradns.com",
  DNSWATCH: "dns.watch",
  CleanBrowsing_Adult_Filter: "cleanbrowsing.org",
  "ControlD-Ads": "controld.com",
  "dns0.eu": "dns0.eu",
  // Verified live (curl'd each, 2026-09-19) — real Iranian companies/services
  // with an unambiguous official site, not community DNS lists.
  SHECAN: "shecan.ir",
  ASIA_TECH: "asiatech.ir",
  Shatel: "shatel.ir",
  Irancell: "irancell.ir"
}

function attachDomains(list) {
  return (list || []).map(function (s) {
    var domain = DOMAIN_BY_KEY[s.key]
    if (!domain) return s
    var copy = {}
    for (var k in s) copy[k] = s[k]
    copy.domain = domain
    return copy
  })
}

function sortByRate(list) {
  return (list || []).slice().sort(function (a, b) { return (b.rate || 0) - (a.rate || 0) })
}

function bundledServers() {
  return attachDomains(sortByRate(BUNDLED_SERVERS))
}

// dns.validator.ts: isValidDnsAddress — plain dotted-quad shape check, no
// octet-range validation (matches the CLI exactly, including its leniency).
function isValidDnsAddress(value) {
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(String(value || ""))
}

// connect.ts's `-s` flag: comma-separated list, first address must be valid;
// a present second address must also be valid. Returns { ok, addresses } or
// { ok:false, error }.
function parseAddressList(input) {
  var raw = String(input || "").split(",").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
  if (raw.length === 0) return { ok: false, error: "Enter at least one DNS address" }
  if (!isValidDnsAddress(raw[0])) return { ok: false, error: "Invalid DNS address: " + raw[0] }
  if (raw[1] && !isValidDnsAddress(raw[1])) return { ok: false, error: "Invalid DNS address: " + raw[1] }
  return { ok: true, addresses: raw.slice(0, 2) }
}

function serverByAddresses(list, addresses) {
  var want = (addresses || []).join(",")
  for (var i = 0; i < (list || []).length; i++) {
    if ((list[i].servers || []).join(",") === want) return list[i]
  }
  return null
}

function serverByName(list, name) {
  var want = String(name || "").toLowerCase()
  for (var i = 0; i < (list || []).length; i++) {
    if (String(list[i].name || "").toLowerCase() === want) return list[i]
  }
  return null
}

// connect.ts: an address list with no catalog match becomes a synthetic
// "custom-<first ip>" server (key === name, rate 0, tags: ["custom"]).
function customServer(addresses) {
  return {
    key: "custom-" + addresses[0],
    name: "custom-" + addresses[0],
    servers: addresses.slice(),
    rate: 0,
    tags: ["custom"]
  }
}

// --- Custom profiles ---------------------------------------------------------
//
// Saved, named custom servers. Not part of the original CLI (its -s flag
// connects to a synthetic customServer() but never persists it); a plugin
// addition so a hand-entered address can be reused instead of retyped.

function makeCustomProfile(name, addresses) {
  var n = String(name || "").trim() || ("custom-" + addresses[0])
  return {
    key: "profile-" + addresses.join("-"),
    name: n,
    servers: addresses.slice(),
    rate: 0,
    tags: ["custom"],
    isCustomProfile: true
  }
}

function loadCustomProfiles(raw) {
  var list
  try { list = JSON.parse(String(raw || "[]")) } catch (e) { return [] }
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (p && Array.isArray(p.servers) && p.servers.length > 0) out.push(makeCustomProfile(p.name, p.servers))
  }
  return out
}

// Add/replace-by-address, returns the new array (caller persists it).
function upsertCustomProfile(list, name, addresses) {
  var want = addresses.join(",")
  var out = (list || []).filter(function (p) { return (p.servers || []).join(",") !== want })
  out.push(makeCustomProfile(name, addresses))
  return out
}

function removeCustomProfile(list, key) {
  return (list || []).filter(function (p) { return p.key !== key })
}

// --- Ping-based sort -------------------------------------------------------
//
// Not part of the original CLI (it has no latency feature). Ascending by
// ping; a timeout (null) or not-yet-pinged (undefined) entry sorts after
// every measured one, tie-broken by rate desc so the list doesn't look
// randomly shuffled before pings land.
function sortByPing(list, pingResults) {
  var results = pingResults || {}
  function pingOf(s) {
    var ip = s.servers && s.servers[0]
    return ip ? results[ip] : undefined
  }
  return (list || []).slice().sort(function (a, b) {
    var pa = pingOf(a), pb = pingOf(b)
    var aKnown = typeof pa === "number", bKnown = typeof pb === "number"
    if (aKnown && bKnown) return pa - pb
    if (aKnown) return -1
    if (bKnown) return 1
    return (b.rate || 0) - (a.rate || 0)
  })
}

function randomServer(list) {
  if (!list || list.length === 0) return null
  return list[Math.floor(Math.random() * list.length)]
}

// status.ts: no active nameservers -> "off"; active list matches a catalog
// entry's addresses exactly -> "known" (with that server); otherwise
// "unknown" (connected, but not to anything in our list — e.g. right after
// disconnect(), whose defaults aren't themselves a catalog entry).
function statusOf(activeIps, servers) {
  var ips = activeIps || []
  if (ips.length === 0) return { state: "off", server: null }
  var match = serverByAddresses(servers || [], ips)
  return match ? { state: "known", server: match } : { state: "unknown", server: null }
}

function tagList(tags) {
  return (tags || []).join(" · ")
}

// --- Provider badges ---------------------------------------------------------
//
// The CLI's Server interface has no logo field (the desktop app's DB has
// `avatar` filenames, but those PNGs aren't bundled here — their license
// wasn't checked, and several are third-party trademarks). Instead each
// server gets a small generated monogram badge: a deterministic color
// (hashed from its key, so it's stable across reloads) plus its initials.
// No third-party artwork is reproduced.

function initials(name) {
  var s = String(name || "").trim()
  if (!s) return "?"
  if (s.indexOf("custom-") === 0) return "C"
  var parts = s.split(/\s+/).filter(function (p) { return p.length > 0 })
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
  return s.slice(0, 2).toUpperCase()
}

function hashString(s) {
  var h = 0
  s = String(s || "")
  for (var i = 0; i < s.length; i++) h = ((h << 5) - h + s.charCodeAt(i)) | 0
  return Math.abs(h)
}

// Returns { h, s, l, a } for Qt.hsla(...) — kept as plain numbers (not a
// QML color) so this file stays free of QML/Quickshell types.
function badgeHsla(key) {
  var hue = (hashString(key) % 360) / 360
  return { h: hue, s: 0.5, l: 0.42, a: 1 }
}

// --- Ping ----------------------------------------------------------------
//
// Not part of the original CLI (it has no latency feature) — a plugin
// addition. `ms` is undefined (not yet pinged), null (timed out /
// unreachable), or a number.
function formatPing(ms) {
  if (ms === undefined) return ""
  if (ms === null) return "timeout"
  return Math.round(ms) + " ms"
}
