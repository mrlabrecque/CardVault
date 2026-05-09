const http = require("node:http");
const crypto = require("node:crypto");
const { URL } = require("node:url");
const { chromium } = require("playwright");

/** Heroku router times out ~30s; background jobs avoid H12 on long Playwright runs */
const IS_HEROKU = Boolean(process.env.DYNO);
const jobs = new Map();
const JOB_TTL_MS = 10 * 60 * 1000;

function pruneJobs() {
  const now = Date.now();
  for (const [id, j] of jobs) {
    if (now - j.createdAt > JOB_TTL_MS) jobs.delete(id);
  }
}

if (typeof setInterval !== "undefined") {
  setInterval(pruneJobs, 60_000);
}

function publicBaseUrl(req) {
  const proto = req.headers["x-forwarded-proto"] || "https";
  const host = req.headers.host || "localhost";
  return `${proto}://${host}`;
}

const PORT = Number(process.env.PORT || 8788);
const API_KEY = process.env.SELF_HOSTED_SCRAPER_API_KEY || "";
const REQUEST_TIMEOUT_MS = Number(process.env.SELF_HOSTED_TIMEOUT_MS || 90000);
const MAX_ITEMS = Number(process.env.SELF_HOSTED_MAX_ITEMS || 60);
const HEADLESS = process.env.SELF_HOSTED_HEADLESS !== "false";
const ATTEMPTS = Math.max(1, Number(process.env.SELF_HOSTED_ATTEMPTS || 3));
const RETRY_BASE_MS = Math.max(100, Number(process.env.SELF_HOSTED_RETRY_BASE_MS || 1500));
/** Default: aggregate eBay sold comps via 130point.com (see README). Use `ebay` for direct eBay HTML (often blocked). */
const SALES_SOURCE = (process.env.SELF_HOSTED_SALES_SOURCE || "130point").toLowerCase();
const POINT_SALES_URL = process.env.SELF_HOSTED_130POINT_URL || "https://130point.com/sales/";
/** On Heroku, 130point often needs a residential proxy; set true to fail fast if none configured. */
const REQUIRE_PROXY_130POINT =
  SALES_SOURCE === "130point" &&
  (process.env.SELF_HOSTED_REQUIRE_PROXY === "true" || process.env.SELF_HOSTED_130POINT_REQUIRE_PROXY === "true");

let cachedProxyConfig = null;
let cachedProxyResolved = false;

/**
 * Playwright proxy for 130point (and ebay mode). Precedence:
 * 1) SELF_HOSTED_PROXY_SERVER (+ USERNAME / PASSWORD)
 * 2) DECODO_PROXY_SERVER (+ USERNAME / PASSWORD) — residential gateway, separate from Scraper API keys
 * 3) SELF_HOSTED_PROXY_URL or DECODO_PROXY_URL — http(s)://user:pass@host:port
 */
function getProxyConfig() {
  if (cachedProxyResolved) return cachedProxyConfig;

  const selfServer = process.env.SELF_HOSTED_PROXY_SERVER || "";
  if (selfServer) {
    cachedProxyConfig = {
      server: selfServer,
      username: process.env.SELF_HOSTED_PROXY_USERNAME || "",
      password: process.env.SELF_HOSTED_PROXY_PASSWORD || "",
    };
    cachedProxyResolved = true;
    return cachedProxyConfig;
  }

  const decodoServer = process.env.DECODO_PROXY_SERVER || "";
  if (decodoServer) {
    cachedProxyConfig = {
      server: decodoServer,
      username: process.env.DECODO_PROXY_USERNAME || "",
      password: process.env.DECODO_PROXY_PASSWORD || "",
    };
    cachedProxyResolved = true;
    return cachedProxyConfig;
  }

  const urlStr = process.env.SELF_HOSTED_PROXY_URL || process.env.DECODO_PROXY_URL || "";
  if (urlStr) {
    try {
      const u = new URL(urlStr);
      cachedProxyConfig = {
        server: `${u.protocol}//${u.host}`,
        username: decodeURIComponent(u.username || ""),
        password: decodeURIComponent(u.password || ""),
      };
      cachedProxyResolved = true;
      return cachedProxyConfig;
    } catch {
      cachedProxyConfig = null;
      cachedProxyResolved = true;
      return null;
    }
  }

  cachedProxyConfig = null;
  cachedProxyResolved = true;
  return null;
}

const USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36",
];

const ACCEPT_LANGUAGES = ["en-US,en;q=0.9", "en-GB,en;q=0.9", "en-US,en;q=0.8"];

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(JSON.stringify(body));
}

function cleanText(value) {
  return (value || "").replace(/\s+/g, " ").trim();
}

function parsePrice(value) {
  if (!value) return null;
  const match = value.replace(/,/g, "").match(/\$?\s*(\d+(?:\.\d+)?)/);
  if (!match) return null;
  const num = Number(match[1]);
  return Number.isFinite(num) ? num : null;
}

function parseSoldDate(value) {
  if (!value) return null;
  const cleaned = cleanText(value).replace(/^Sold\s*/i, "");
  const parsed = Date.parse(cleaned);
  if (!Number.isFinite(parsed)) return null;
  return new Date(parsed).toISOString();
}

function isEbaySecurityPage(html) {
  const haystack = (html || "").toLowerCase();
  return (
    haystack.includes("security measure") ||
    haystack.includes("access denied") ||
    haystack.includes("robot check") ||
    haystack.includes("automated access")
  );
}

function isCloudflareChallenge(html, title) {
  const t = (title || "").toLowerCase();
  const h = (html || "").toLowerCase();
  return (
    t.includes("just a moment") ||
    t.includes("attention required") ||
    h.includes("challenges.cloudflare.com") ||
    h.includes("cf-browser-verification") ||
    h.includes("enable javascript and cookies to continue")
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function pick(arr, seed) {
  return arr[seed % arr.length];
}

function toErr(code, message) {
  const err = new Error(message || code);
  err.code = code;
  return err;
}

function buildProxy() {
  const cfg = getProxyConfig();
  if (!cfg || !cfg.server) return undefined;
  const proxy = { server: cfg.server };
  if (cfg.username) proxy.username = cfg.username;
  if (cfg.password) proxy.password = cfg.password;
  return proxy;
}

async function waitPastCloudflare(page) {
  const maxMs = Math.min(
    IS_HEROKU ? 22000 : 75000,
    REQUEST_TIMEOUT_MS,
  );
  const started = Date.now();
  while (Date.now() - started < maxMs) {
    try {
      await page.waitForLoadState("domcontentloaded", { timeout: 5000 }).catch(() => {});
      const title = await page.title();
      let html = "";
      try {
        html = await page.content();
      } catch (e) {
        const msg = String(e?.message ?? e);
        if (msg.includes("navigating") || msg.includes("Target closed")) {
          await sleep(1200);
          continue;
        }
        throw e;
      }
      if (!isCloudflareChallenge(html, title)) return;
    } catch {
      await sleep(1000);
    }
    await sleep(1500);
  }
  throw toErr("cf_challenge_page", "cf_challenge_page");
}

async function scrapeEbayOnce({ query, maxItems, attempt }) {
  const targetUrl = new URL("https://www.ebay.com/sch/i.html");
  targetUrl.searchParams.set("_nkw", query);
  targetUrl.searchParams.set("LH_Sold", "1");
  targetUrl.searchParams.set("LH_Complete", "1");
  targetUrl.searchParams.set("rt", "nc");

  const browser = await chromium.launch({
    headless: HEADLESS,
    proxy: buildProxy(),
    args: [
      "--disable-dev-shm-usage",
      "--disable-blink-features=AutomationControlled",
      "--no-sandbox",
    ],
  });

  try {
    const userAgent = process.env.SELF_HOSTED_USER_AGENT || pick(USER_AGENTS, attempt);
    const context = await browser.newContext({
      userAgent,
      viewport: { width: 1366 + ((attempt * 37) % 240), height: 900 + ((attempt * 31) % 380) },
      locale: "en-US",
      timezoneId: "America/New_York",
    });
    const page = await context.newPage();
    await context.setExtraHTTPHeaders({
      "accept-language": pick(ACCEPT_LANGUAGES, attempt),
      "upgrade-insecure-requests": "1",
      "sec-ch-ua-mobile": "?0",
      dnt: "1",
    });

    await page.addInitScript(() => {
      Object.defineProperty(navigator, "webdriver", { get: () => false });
    });

    await page.goto(targetUrl.toString(), {
      waitUntil: "networkidle",
      timeout: REQUEST_TIMEOUT_MS,
    });
    await sleep(800 + Math.floor(Math.random() * 1000));
    await page.mouse.move(100 + attempt * 20, 280 + attempt * 15);
    await page.mouse.wheel(0, 500 + attempt * 120);
    await sleep(400 + Math.floor(Math.random() * 600));

    const html = await page.content();
    if (isEbaySecurityPage(html)) {
      throw toErr("ebay_bot_protection_page", "ebay_bot_protection_page");
    }

    await page.waitForSelector(".s-item", {
      timeout: Math.min(15000, REQUEST_TIMEOUT_MS),
    });

    const rows = await page.$$eval(
      ".srp-results .s-item",
      (nodes, limit) => {
        const out = [];
        for (const node of nodes) {
          if (out.length >= limit) break;
          const titleEl = node.querySelector(".s-item__title");
          const title = titleEl?.textContent?.trim() || "";
          if (!title || title.toLowerCase().includes("shop on ebay")) continue;

          const priceEl = node.querySelector(".s-item__price");
          const dateEl =
            node.querySelector(".s-item__title--tagblock .POSITIVE") ||
            node.querySelector(".s-item__title--tag");
          const linkEl = node.querySelector(".s-item__link");
          const imageEl = node.querySelector(".s-item__image-img");

          out.push({
            title,
            priceText: priceEl?.textContent?.trim() || "",
            soldDateText: dateEl?.textContent?.trim() || "",
            itemWebUrl: linkEl?.getAttribute("href") || "",
            imageUrl: imageEl?.getAttribute("src") || "",
          });
        }
        return out;
      },
      Math.min(maxItems, MAX_ITEMS)
    );

    return rows.map((item) => ({
      title: cleanText(item.title),
      price: parsePrice(item.priceText),
      soldDate: parseSoldDate(item.soldDateText),
      itemWebUrl: cleanText(item.itemWebUrl),
      imageUrl: cleanText(item.imageUrl),
      source: "self_hosted_ebay",
    }));
  } finally {
    await browser.close();
  }
}

async function submit130PointSearch(page, query) {
  const candidates = [
    'input[type="search"]',
    'input[placeholder*="Search" i]',
    'input[placeholder*="search" i]',
    'input[aria-label*="Search" i]',
    'main input[type="text"]',
    'form input[type="text"]',
    "#search",
    'input[name="q"]',
    'input[name="search"]',
  ];

  let filled = false;
  for (const sel of candidates) {
    const loc = page.locator(sel).first();
    try {
      await loc.waitFor({ state: "visible", timeout: 8000 });
      await loc.click({ timeout: 3000 });
      await loc.fill("");
      await loc.fill(query);
      filled = true;
      break;
    } catch {
      continue;
    }
  }

  if (!filled) {
    throw toErr("scrape_failed", "130point_search_input_not_found");
  }

  const searchBtn = page.getByRole("button", { name: /search/i }).first();
  try {
    await searchBtn.click({ timeout: 5000 });
  } catch {
    await page.keyboard.press("Enter");
  }

  await sleep(IS_HEROKU ? 600 : 1500 + Math.floor(Math.random() * 800));
}

async function extract130PointRows(page, limit) {
  return page.evaluate((max) => {
    function cleanText(s) {
      return (s || "").replace(/\s+/g, " ").trim();
    }

    const priceRe = /\$\s*[\d,]+(?:\.\d{2})?/;
    const dateRe =
      /\d{1,2}\/\d{1,2}\/\d{2,4}|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2},? \d{4}\b/i;

    function rowFromTr(tr) {
      const tds = tr.querySelectorAll("td");
      if (tds.length < 2) return null;
      const fullText = tr.innerText.replace(/\s+/g, " ").trim();
      const headerish = /^(title|price|date|sold|image|listing)/i.test(fullText.slice(0, 40));
      if (headerish && fullText.length < 80) return null;

      const priceMatch = fullText.match(priceRe);
      if (!priceMatch) return null;

      const dateMatch = fullText.match(dateRe);
      const link =
        tr.querySelector('a[href*="ebay"]') ||
        tr.querySelector('a[href*="130point"]') ||
        tr.querySelector("a[href^='http']");
      const img = tr.querySelector("img[src]");

      let title = "";
      if (tds.length >= 3) title = cleanText(tds[1]?.innerText || "");
      else if (tds.length >= 2) title = cleanText(tds[0]?.innerText || "");
      if (!title || title.length < 3) {
        title = fullText.split("$")[0].trim().slice(0, 280);
      }

      return {
        title,
        priceText: priceMatch[0],
        soldDateText: dateMatch ? dateMatch[0] : "",
        itemWebUrl: link?.href || "",
        imageUrl: img?.src || "",
      };
    }

    const out = [];
    const trs = Array.from(document.querySelectorAll("table tbody tr"));
    for (const tr of trs) {
      if (out.length >= max) break;
      const row = rowFromTr(tr);
      if (row && row.title.length > 2) out.push(row);
    }

    if (out.length === 0) {
      const altRows = Array.from(document.querySelectorAll('[class*="border-b"], [data-testid*="row"]')).slice(
        0,
        max * 2
      );
      for (const el of altRows) {
        if (out.length >= max) break;
        const fullText = el.innerText.replace(/\s+/g, " ").trim();
        const pm = fullText.match(priceRe);
        if (!pm || fullText.length < 20) continue;
        const dm = fullText.match(dateRe);
        const link = el.querySelector("a[href]");
        const img = el.querySelector("img[src]");
        const title = fullText.split("$")[0].trim().slice(0, 280);
        if (title.length > 3) {
          out.push({
            title,
            priceText: pm[0],
            soldDateText: dm ? dm[0] : "",
            itemWebUrl: link?.href || "",
            imageUrl: img?.src || "",
          });
        }
      }
    }

    return out;
  }, Math.min(limit, MAX_ITEMS));
}

async function scrape130PointOnce({ query, maxItems, attempt }) {
  if (REQUIRE_PROXY_130POINT && !buildProxy()) {
    throw toErr("proxy_required", "130point requires SELF_HOSTED_PROXY_* or DECODO_PROXY_* (set SELF_HOSTED_REQUIRE_PROXY=false to override)");
  }

  const browser = await chromium.launch({
    headless: HEADLESS,
    proxy: buildProxy(),
    args: [
      "--disable-dev-shm-usage",
      "--disable-blink-features=AutomationControlled",
      "--no-sandbox",
    ],
  });

  try {
    const userAgent = process.env.SELF_HOSTED_USER_AGENT || pick(USER_AGENTS, attempt);
    const context = await browser.newContext({
      userAgent,
      viewport: { width: 1366 + ((attempt * 37) % 240), height: 900 + ((attempt * 31) % 380) },
      locale: "en-US",
      timezoneId: "America/New_York",
    });
    const page = await context.newPage();
    await context.setExtraHTTPHeaders({
      "accept-language": pick(ACCEPT_LANGUAGES, attempt),
      "upgrade-insecure-requests": "1",
      "sec-ch-ua-mobile": "?0",
      dnt: "1",
    });

    await page.addInitScript(() => {
      Object.defineProperty(navigator, "webdriver", { get: () => false });
    });

    await page.goto(POINT_SALES_URL, {
      waitUntil: "domcontentloaded",
      timeout: REQUEST_TIMEOUT_MS,
    });

    await waitPastCloudflare(page);

    await submit130PointSearch(page, query);

    // Avoid networkidle — too slow; Heroku H12 is ~30s on the sync HTTP path.
    await page.waitForLoadState("domcontentloaded", { timeout: 8000 }).catch(() => {});
    await sleep(IS_HEROKU ? 1200 : 800 + Math.floor(Math.random() * 700));

    try {
      await page.waitForSelector("table tbody tr, main table, [class*='result']", {
        timeout: Math.min(IS_HEROKU ? 12000 : 35000, REQUEST_TIMEOUT_MS),
      });
    } catch {
      /* continue — extraction may still find rows */
    }

    await sleep(IS_HEROKU ? 400 : 800 + Math.floor(Math.random() * 700));

    const html = await page.content();
    if (isCloudflareChallenge(html, await page.title())) {
      throw toErr("cf_challenge_page", "cf_challenge_page");
    }

    const rawRows = await extract130PointRows(page, Math.min(maxItems, MAX_ITEMS));

    return rawRows.map((item) => ({
      title: cleanText(item.title),
      price: parsePrice(item.priceText),
      soldDate: parseSoldDate(item.soldDateText),
      itemWebUrl: cleanText(item.itemWebUrl),
      imageUrl: cleanText(item.imageUrl),
      source: "self_hosted_130point",
    }));
  } finally {
    await browser.close();
  }
}

async function scrapeOnce(params) {
  if (SALES_SOURCE === "ebay") {
    return scrapeEbayOnce(params);
  }
  return scrape130PointOnce(params);
}

async function scrapeSoldListings({ query, maxItems }) {
  let lastError = null;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    try {
      const items = await scrapeOnce({ query, maxItems, attempt });
      if (items.length > 0) return items;
      throw toErr("no_results", "no_results");
    } catch (error) {
      lastError = error;
      const code = error && typeof error === "object" ? error.code : "";
      const isHardBlock =
        String(code || "").includes("ebay_bot_protection_page") ||
        String(code || "").includes("cf_challenge_page");
      const isLast = attempt >= ATTEMPTS;
      if (isLast) break;
      const backoff = RETRY_BASE_MS * Math.pow(2, attempt - 1) + Math.floor(Math.random() * 600);
      console.warn(
        `[self-hosted-scraper] attempt ${attempt}/${ATTEMPTS} failed (${String(code || error)}), retrying in ${backoff}ms`
      );
      await sleep(backoff);
      if (!isHardBlock) continue;
      await sleep(1200 + Math.floor(Math.random() * 1200));
    }
  }
  throw lastError || toErr("scrape_failed", "scrape_failed");
}

function parseJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) reject(new Error("payload_too_large"));
    });
    req.on("end", () => {
      if (!body) return resolve({});
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error("invalid_json"));
      }
    });
    req.on("error", reject);
  });
}

function requireApiKey(req, res) {
  if (!API_KEY) return true;
  if (req.headers["x-api-key"] !== API_KEY) {
    json(res, 401, { error: "unauthorized" });
    return false;
  }
  return true;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

    if (req.method === "GET" && url.pathname === "/health") {
      const proxyConfigured = Boolean(getProxyConfig()?.server);
      return json(res, 200, {
        ok: true,
        service: "self-hosted-scraper",
        salesSource: SALES_SOURCE,
        asyncJobs: true,
        proxyConfigured,
        requireProxy130point: REQUIRE_PROXY_130POINT,
      });
    }

    if (req.method === "GET" && url.pathname.startsWith("/sold-listings/jobs/")) {
      if (!requireApiKey(req, res)) return;
      const jobId = url.pathname.replace(/^\/sold-listings\/jobs\//, "").replace(/\/.*$/, "");
      if (!jobId) return json(res, 400, { error: "missing_job_id" });
      pruneJobs();
      const job = jobs.get(jobId);
      if (!job) return json(res, 404, { error: "job_not_found", jobId });
      if (job.status === "pending") {
        return json(res, 200, { jobId, status: "pending" });
      }
      if (job.status === "done") {
        return json(res, 200, {
          jobId,
          status: "done",
          items: job.items,
          count: job.items.length,
          salesSource: SALES_SOURCE,
        });
      }
      return json(res, 200, {
        jobId,
        status: "failed",
        error: job.error,
        code: job.code || "scrape_failed",
      });
    }

    if (req.method !== "POST" || url.pathname !== "/sold-listings") {
      return json(res, 404, { error: "not_found" });
    }

    if (!requireApiKey(req, res)) return;

    const body = await parseJsonBody(req);
    const query = cleanText(body.query);
    const maxItems = Number(body.maxItems || MAX_ITEMS);
    if (!query) return json(res, 400, { error: "missing_query" });

    const useAsync = body.async === true;
    if (useAsync) {
      pruneJobs();
      const jobId = crypto.randomUUID();
      jobs.set(jobId, { status: "pending", createdAt: Date.now() });
      const base = publicBaseUrl(req);
      const pollPath = `/sold-listings/jobs/${jobId}`;
      setImmediate(() => {
        scrapeSoldListings({ query, maxItems })
          .then((items) => {
            jobs.set(jobId, {
              status: "done",
              items,
              createdAt: Date.now(),
            });
          })
          .catch((err) => {
            const code = err && typeof err === "object" && err.code ? err.code : "scrape_failed";
            jobs.set(jobId, {
              status: "failed",
              error: err instanceof Error ? err.message : String(err),
              code,
              createdAt: Date.now(),
            });
          });
      });
      return json(res, 202, {
        jobId,
        status: "pending",
        pollUrl: `${base}${pollPath}`,
      });
    }

    const startedAt = Date.now();
    const items = await scrapeSoldListings({ query, maxItems });
    return json(res, 200, {
      query,
      count: items.length,
      elapsedMs: Date.now() - startedAt,
      items,
      salesSource: SALES_SOURCE,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const code = error && typeof error === "object" ? error.code : undefined;
    const status =
      code === "ebay_bot_protection_page" || code === "cf_challenge_page" ? 429 : 500;
    return json(res, status, {
      error: code || "scrape_failed",
      message,
    });
  }
});

server.listen(PORT, "0.0.0.0", () => {
  const hasProxy = Boolean(getProxyConfig()?.server);
  console.log(`[self-hosted-scraper] listening on :${PORT} (source=${SALES_SOURCE}, proxy=${hasProxy})`);
  if (IS_HEROKU && SALES_SOURCE === "130point" && !hasProxy) {
    console.warn(
      "[self-hosted-scraper] 130point on Heroku without proxy — set DECODO_PROXY_* or SELF_HOSTED_PROXY_* (see README)",
    );
  }
});
