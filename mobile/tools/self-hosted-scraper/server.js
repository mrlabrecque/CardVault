const http = require("node:http");
const { URL } = require("node:url");
const { chromium } = require("playwright");

const PORT = Number(process.env.PORT || 8788);
const API_KEY = process.env.SELF_HOSTED_SCRAPER_API_KEY || "";
const REQUEST_TIMEOUT_MS = Number(process.env.SELF_HOSTED_TIMEOUT_MS || 90000);
const MAX_ITEMS = Number(process.env.SELF_HOSTED_MAX_ITEMS || 60);
const HEADLESS = process.env.SELF_HOSTED_HEADLESS !== "false";
const ATTEMPTS = Math.max(1, Number(process.env.SELF_HOSTED_ATTEMPTS || 3));
const RETRY_BASE_MS = Math.max(100, Number(process.env.SELF_HOSTED_RETRY_BASE_MS || 1500));
const PROXY_SERVER = process.env.SELF_HOSTED_PROXY_SERVER || "";
const PROXY_USERNAME = process.env.SELF_HOSTED_PROXY_USERNAME || "";
const PROXY_PASSWORD = process.env.SELF_HOSTED_PROXY_PASSWORD || "";

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
  if (!PROXY_SERVER) return undefined;
  const proxy = { server: PROXY_SERVER };
  if (PROXY_USERNAME) proxy.username = PROXY_USERNAME;
  if (PROXY_PASSWORD) proxy.password = PROXY_PASSWORD;
  return proxy;
}

async function scrapeOnce({ query, maxItems, attempt }) {
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
    await page.waitForTimeout(800 + Math.floor(Math.random() * 1000));
    await page.mouse.move(100 + attempt * 20, 280 + attempt * 15);
    await page.mouse.wheel(0, 500 + attempt * 120);
    await page.waitForTimeout(400 + Math.floor(Math.random() * 600));

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
      source: "self_hosted_playwright",
    }));
  } finally {
    await browser.close();
  }
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
      const isBlock = String(code || "").includes("ebay_bot_protection_page");
      const isLast = attempt >= ATTEMPTS;
      if (isLast) break;
      const backoff = RETRY_BASE_MS * Math.pow(2, attempt - 1) + Math.floor(Math.random() * 600);
      console.warn(
        `[self-hosted-scraper] attempt ${attempt}/${ATTEMPTS} failed (${String(code || error)}), retrying in ${backoff}ms`
      );
      await sleep(backoff);
      if (!isBlock) continue;
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

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);

    if (req.method === "GET" && url.pathname === "/health") {
      return json(res, 200, { ok: true, service: "self-hosted-scraper" });
    }

    if (req.method !== "POST" || url.pathname !== "/sold-listings") {
      return json(res, 404, { error: "not_found" });
    }

    if (API_KEY) {
      const incoming = req.headers["x-api-key"];
      if (incoming !== API_KEY) return json(res, 401, { error: "unauthorized" });
    }

    const body = await parseJsonBody(req);
    const query = cleanText(body.query);
    const maxItems = Number(body.maxItems || MAX_ITEMS);
    if (!query) return json(res, 400, { error: "missing_query" });

    const startedAt = Date.now();
    const items = await scrapeSoldListings({ query, maxItems });
    return json(res, 200, {
      query,
      count: items.length,
      elapsedMs: Date.now() - startedAt,
      items,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const code = error && typeof error === "object" ? error.code : undefined;
    return json(res, code === "ebay_bot_protection_page" ? 429 : 500, {
      error: code || "scrape_failed",
      message,
    });
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`[self-hosted-scraper] listening on :${PORT}`);
});
