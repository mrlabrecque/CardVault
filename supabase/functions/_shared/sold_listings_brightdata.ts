/**
 * Sold listings via Bright Data Web Unlocker — eBay completed search HTML + optional
 * per-listing unlock for “Best offer accepted” rows (off by default; see DEFAULT_MAX_BO_DETAIL).
 *
 * Transport: async POST /unblocker/req + poll when customer id is known; otherwise sync POST /request.
 * If async returns HTML errors or times out polling, we fall back to sync (disable with BRIGHTDATA_ASYNC_FALLBACK_SYNC=false).
 * Force sync only: BRIGHTDATA_SYNC_UNLOCK=true.
 *
 * @see https://docs.brightdata.com/scraping-automation/web-unlocker/introduction
 * @see https://docs.brightdata.com/scraping-automation/web-unlocker/your-first-async-request
 */

const BRIGHTDATA_REQUEST_URL = 'https://api.brightdata.com/request';
/** Async Unlocker — submit job then poll (recommended for slow targets like eBay). */
const BRIGHTDATA_UNBLOCKER_REQ_URL = 'https://api.brightdata.com/unblocker/req';
const BRIGHTDATA_UNBLOCKER_GET_RESULT_URL = 'https://api.brightdata.com/unblocker/get_result';
/** Max age of sold listings to keep. Override via BRIGHTDATA_SOLD_LOOKBACK_DAYS — see soldLookbackDays(). */
const DEFAULT_SOLD_LOOKBACK_DAYS = 90;
const MAX_SOLD_LOOKBACK_DAYS = 1095;
const MAX_RETRIES = 2;
const RETRY_BASE_MS = 800;
/** Hard cap on SERP rows parsed (product requirement). */
export const BRIGHTDATA_MAX_SERP_ITEMS = 80;
/** Default 0: listing-detail unlocks are expensive and often exceed Edge CPU/time budgets; set env to enable. */
const DEFAULT_MAX_BO_DETAIL = 0;
const BO_DETAIL_CONCURRENCY = 3;
const BO_DETAIL_BATCH_DELAY_MS = 400;

/** Sync POST /request — single long HTTP round-trip (fallback when async poll misbehaves). */
const DEFAULT_SEARCH_TIMEOUT_MS = 110_000;
const DEFAULT_LISTING_TIMEOUT_MS = 15_000;
/** Bright Data: async jobs can take minutes on heavy targets; Edge runtime may cap earlier than this. */
const DEFAULT_ASYNC_POLL_MAX_MS = 300_000;
const DEFAULT_ASYNC_POLL_INTERVAL_MS = 2_500;
const DEFAULT_ASYNC_HTTP_MS = 90_000;

/** From Unlocker “Access details” proxy user, e.g. `brd-customer-hl_91fe46ae-zone-card_locker_api`. */
export function parseBrightDataProxyUsername(
  raw: string,
): { customer: string; zone: string } | null {
  const s = raw.trim();
  const needle = '-zone-';
  const i = s.indexOf(needle);
  if (!s.startsWith('brd-customer-') || i === -1) return null;
  const customer = s.slice('brd-customer-'.length, i);
  const zone = s.slice(i + needle.length);
  if (!customer || !zone) return null;
  return { customer, zone };
}

export type BrightDataCtxSource =
  | 'proxy_username'
  | 'customer_id_full_line'
  | 'env_split'
  /** `BRIGHTDATA_PROXY_USERNAME` is set but does not match `brd-customer-*-zone-*` — zone/customer come from UNLOCKER_ZONE + CUSTOMER_ID instead. */
  | 'env_split_bad_proxy';

export type BrightDataUnlockerCtx = {
  apiKey: string;
  zone: string;
  /** Account id for async `/unblocker/*` query param `customer` — required for JSON poll responses. */
  customer: string;
  /** Which secrets were used for zone + customer (when both proxy and split vars exist, parsed proxy wins). */
  ctxSource: BrightDataCtxSource;
};

/** Prefer `BRIGHTDATA_PROXY_USERNAME` (full brd-customer-…-zone-…) so zone + customer always match. */
export function resolveBrightDataUnlockerContext(): BrightDataUnlockerCtx {
  const rawKey = Deno.env.get('BRIGHTDATA_API_KEY') ?? '';
  if (/[\r\n]/.test(rawKey)) {
    console.warn('[sold-listings-brightdata] BRIGHTDATA_API_KEY contains a line break — paste the key as one line in Supabase secrets');
  }
  const apiKey = rawKey.trim();
  const proxyLine = (Deno.env.get('BRIGHTDATA_PROXY_USERNAME') ?? '').trim();

  let zone = (Deno.env.get('BRIGHTDATA_UNLOCKER_ZONE') ?? '').trim();
  let customer = (Deno.env.get('BRIGHTDATA_CUSTOMER_ID') ?? '').trim();
  let ctxSource: BrightDataCtxSource = 'env_split';

  if (proxyLine) {
    const parsed = parseBrightDataProxyUsername(proxyLine);
    if (parsed) {
      zone = parsed.zone;
      customer = parsed.customer;
      ctxSource = 'proxy_username';
    } else {
      ctxSource = 'env_split_bad_proxy';
      console.warn(
        '[sold-listings-brightdata] BRIGHTDATA_PROXY_USERNAME set but not parseable as brd-customer-*-zone-* — using BRIGHTDATA_UNLOCKER_ZONE + BRIGHTDATA_CUSTOMER_ID instead. Expected shape: brd-customer-hl_xxxx-zone-my_zone (hyphens, single -zone- segment).',
      );
    }
  } else {
    // Common mistake: paste full Access details user into CUSTOMER_ID instead of PROXY_USERNAME.
    const parsedCustomer = parseBrightDataProxyUsername(customer);
    if (parsedCustomer) {
      zone = parsedCustomer.zone;
      customer = parsedCustomer.customer;
      ctxSource = 'customer_id_full_line';
      console.log(
        '[sold-listings-brightdata] parsed BRIGHTDATA_CUSTOMER_ID as full brd-customer-*-zone-* (use BRIGHTDATA_PROXY_USERNAME for clarity)',
      );
    }
  }

  return { apiKey, zone, customer, ctxSource };
}

/** Sold listings older than this many days are dropped; default 90. Set BRIGHTDATA_SOLD_LOOKBACK_DAYS (1–1095). */
export function soldLookbackDays(): number {
  const raw = Deno.env.get('BRIGHTDATA_SOLD_LOOKBACK_DAYS');
  const parsed = raw != null && raw.trim() !== '' ? Number(raw.trim()) : DEFAULT_SOLD_LOOKBACK_DAYS;
  if (!Number.isFinite(parsed)) return DEFAULT_SOLD_LOOKBACK_DAYS;
  return Math.min(MAX_SOLD_LOOKBACK_DAYS, Math.max(1, Math.floor(parsed)));
}

export function resolveSaleType(buying_format: string | null): string {
  const fmt = (buying_format ?? '').toLowerCase();
  if (fmt.includes('auction')) return 'auction';
  if (fmt.includes('best offer') || fmt.includes('best_offer')) return 'best_offer';
  return 'fixed_price';
}

export function parsePrice(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.replace(/[^0-9.]/g, ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

function htmlToText(value: string): string {
  return value
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function extractFirstMatch(input: string, regex: RegExp): string | null {
  const match = regex.exec(input);
  return match?.[1]?.trim() ?? null;
}

function parseSoldDate(value: string): string | null {
  const cleaned = value.replace(/^sold\s*/i, '').trim();
  if (!cleaned) return null;
  const parsed = new Date(cleaned);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export function isEbaySecurityPage(html: string): boolean {
  const t = html.toLowerCase();
  return t.includes('<title>security measure') ||
    t.includes('pardon our interruption') ||
    t.includes('automated access to ebay') ||
    t.includes('let\'s confirm you\'re human') ||
    t.includes('lets confirm you\'re human') ||
    t.includes('verify your identity') ||
    t.includes('additional verification required') ||
    t.includes('press & hold') ||
    t.includes('press and hold') ||
    t.includes('robot check') ||
    t.includes('verify you are human') ||
    t.includes('please enable js and disable any ad blocker') ||
    /\bcaptcha\b/i.test(html) ||
    (t.includes('access denied') && t.includes('ebay'));
}

function shouldCheckEbaySecurity(targetUrl: string): boolean {
  try {
    const host = new URL(targetUrl).hostname.toLowerCase();
    return host === 'ebay.com' || host.endsWith('.ebay.com');
  } catch {
    return false;
  }
}

/**
 * Bright Data sometimes returns the unlocked target page as raw `text/html` (no `{ status_code, body }` JSON).
 * In that case the document is real eBay HTML — not a Bright Data login/error page.
 */
function isLikelyRawUnlockedEbayHtml(html: string): boolean {
  const raw = html.trimStart();
  const head = raw.slice(0, 512).toLowerCase();
  if (!head.startsWith('<!doctype') && !head.startsWith('<html')) return false;

  const sample = html.slice(0, Math.min(html.length, 150_000)).toLowerCase();
  const titleEarly = html.slice(0, 8000).match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? '';
  if (/bright\s*data/i.test(titleEarly)) return false;

  if (sample.includes('ebay.com') || sample.includes('ebaydesc')) return true;
  if (sample.includes('class="x-page-config"') || sample.includes("class='x-page-config'")) return true;
  if (/\bs-item__/.test(html)) return true;

  const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  const title = (titleMatch?.[1] ?? '').replace(/\s+/g, ' ').trim();
  if (/\|\s*ebay\s*$/i.test(title)) return true;

  return false;
}

/** eBay SERP cards — `s-item` may appear anywhere on `<li>` (not only in `class="..."`). */
function extractSerpItemLiBlocks(html: string): string[] {
  const permissive = html.match(/<li\b[^>]*\bs-item\b[^>]*>[\s\S]*?<\/li>/gi) ?? [];
  if (permissive.length > 0) return permissive;
  return html.match(
    /<li\b[^>]*class\s*=\s*(?:"[^"]*\bs-item\b[^"]*"|'[^']*\bs-item\b[^']*'|[^\s>]*\bs-item\b[^\s>]*)[^>]*>[\s\S]*?<\/li>/gi,
  ) ?? [];
}

/**
 * Many eBay URLs include a slug: `/itm/2024-Prizm-Juan-Soto-Downtown-/395847362851`.
 * Use it when DOM titles are missing (modern SERP bundles markup differently).
 */
function titleFromEbayItemUrl(rawHref: string): string | null {
  try {
    const normalized = rawHref.startsWith('http')
      ? rawHref
      : `https://www.ebay.com${rawHref.startsWith('/') ? rawHref : `/${rawHref}`}`;
    const u = new URL(normalized);
    const parts = u.pathname.split('/').filter(Boolean);
    const i = parts.indexOf('itm');
    if (i === -1 || i + 1 >= parts.length) return null;
    const rest = parts.slice(i + 1);
    const last = rest[rest.length - 1];
    if (rest.length >= 2 && /^\d{8,}$/.test(last)) {
      const slugParts = rest.slice(0, -1);
      const slug = slugParts.join('-');
      if (!slug || /^\d+$/.test(slug)) return null;
      const t = decodeURIComponent(slug).replace(/-/g, ' ').replace(/\s+/g, ' ').trim();
      return t.length >= 8 ? t.slice(0, 500) : null;
    }
    if (rest.length === 1) {
      const seg = decodeURIComponent(rest[0]);
      if (/^\d{8,}$/.test(seg)) return null;
      const t = seg.replace(/-/g, ' ').replace(/\s+/g, ' ').trim();
      return t.length >= 8 ? t.slice(0, 500) : null;
    }
  } catch {
    return null;
  }
  return null;
}

/** eBay often sets aria/title on the `/itm/` link to the generic "Sold Item" — skip and prefer real card titles. */
function isGarbageListingTitle(s: string): boolean {
  const t = s.trim();
  if (t.length < 6) return true;
  if (/^sold item$/i.test(t)) return true;
  if (/^(opens in a new window|shop on ebay)$/i.test(t)) return true;
  return false;
}

/**
 * Pull the longest plausible listing title from a SERP HTML window (multiple `s-item__title` nodes, JSON, attrs).
 */
function extractListingTitleFromSerpWindow(win: string, anchorOpenTag: string): string {
  const candidates: string[] = [];

  const pushClean = (raw: string | null | undefined) => {
    const t = htmlToText(raw ?? '').replace(/^new listing\s*/i, '').trim();
    if (!isGarbageListingTitle(t)) candidates.push(t);
  };

  let r = /<span[^>]*class\s*=\s*["'][^"']*s-item__title[^"']*["'][^>]*>([\s\S]*?)<\/span>/gi;
  let sm: RegExpExecArray | null;
  while ((sm = r.exec(win)) !== null) pushClean(sm[1]);

  r = /<div[^>]*class\s*=\s*["'][^"']*s-item__title[^"']*["'][^>]*>([\s\S]*?)<\/div>/gi;
  while ((sm = r.exec(win)) !== null) pushClean(sm[1]);

  r = /<span[^>]*role\s*=\s*["']heading["'][^>]*>([\s\S]*?)<\/span>/gi;
  while ((sm = r.exec(win)) !== null) pushClean(sm[1]);

  r = /<h3[^>]*class\s*=\s*["'][^"']*\bs-item[^"']*["'][^>]*>([\s\S]*?)<\/h3>/gi;
  while ((sm = r.exec(win)) !== null) pushClean(sm[1]);

  if (candidates.length > 0) {
    return candidates.sort((a, b) => b.length - a.length)[0].slice(0, 500);
  }

  pushClean(extractFirstMatch(anchorOpenTag, /\btitle\s*=\s*["']([^"']+)["']/i));
  pushClean(extractFirstMatch(anchorOpenTag, /\baria-label\s*=\s*["']([^"']+)["']/i));

  const jsonTitle = extractFirstMatch(win, /"title"\s*:\s*"([^"]{16,500})"/);
  pushClean(jsonTitle);

  if (candidates.length > 0) {
    return candidates.sort((a, b) => b.length - a.length)[0].slice(0, 500);
  }

  const rawFallback =
    extractFirstMatch(anchorOpenTag, /\btitle\s*=\s*["']([^"']+)["']/i) ??
    extractFirstMatch(anchorOpenTag, /\baria-label\s*=\s*["']([^"']+)["']/i) ??
    '';
  const fallback = htmlToText(rawFallback).slice(0, 500);
  return isGarbageListingTitle(fallback) ? '' : fallback;
}

/**
 * Modern SERPs embed listing titles in JSON blobs / microdata while omitting classic `s-item__title` nodes.
 */
function extractEmbeddedListingTitle(html: string, itemId: string, win: string): string {
  const idEsc = itemId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const chunks: string[] = [];
  if (win.length > 80) chunks.push(win);

  let searchIdx = 0;
  for (let k = 0; k < 4; k++) {
    const idx = html.indexOf(itemId, searchIdx);
    if (idx === -1) break;
    chunks.push(html.slice(Math.max(0, idx - 5_000), idx + 45_000));
    searchIdx = idx + itemId.length;
  }

  const cleanJsonTitle = (raw: string): string =>
    htmlToText(raw.replace(/\\"/g, '"').replace(/\\\\/g, '\\')).trim();

  for (const chunk of chunks) {
    if (chunk.length < 80) continue;

    const patterns = [
      new RegExp(
        `"listingId"\\s*:\\s*"${idEsc}"[\\s\\S]{0,18000}?"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.)+)"`,
        'i',
      ),
      new RegExp(
        `"listingId"\\s*:\\s*${idEsc}\\b[\\s\\S]{0,18000}?"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.)+)"`,
        'i',
      ),
      new RegExp(
        `"itemId"\\s*:\\s*"${idEsc}"[\\s\\S]{0,18000}?"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.)+)"`,
        'i',
      ),
      new RegExp(`${idEsc}[\\s\\S]{0,18000}?"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.){16,})"`, 'i'),
      new RegExp(`"title"\\s*:\\s*"((?:[^"\\\\]|\\\\.){16,})"[\\s\\S]{0,18000}?${idEsc}`, 'i'),
    ];

    for (const rx of patterns) {
      const raw = extractFirstMatch(chunk, rx);
      if (raw) {
        const t = cleanJsonTitle(raw);
        if (!isGarbageListingTitle(t) && t.length >= 12) return t.slice(0, 500);
      }
    }

    const micro = extractFirstMatch(
      chunk,
      /<[^>]*\bitemprop\s*=\s*["']name["'][^>]*\bcontent\s*=\s*["']([^"']{16,})["']/i,
    );
    if (micro) {
      const t = htmlToText(micro.replace(/&amp;/g, '&'));
      if (!isGarbageListingTitle(t)) return t.slice(0, 500);
    }

    const dataTitle = extractFirstMatch(chunk, /\bdata-item-title\s*=\s*["']([^"']{16,})["']/i);
    if (dataTitle) {
      const t = htmlToText(dataTitle.replace(/&amp;/g, '&'));
      if (!isGarbageListingTitle(t)) return t.slice(0, 500);
    }

    const metaName = extractFirstMatch(
      chunk,
      /<meta\b[^>]*itemprop\s*=\s*["']name["'][^>]*content\s*=\s*["']([^"']{16,})["']/i,
    );
    if (metaName) {
      const t = htmlToText(metaName.replace(/&amp;/g, '&'));
      if (!isGarbageListingTitle(t)) return t.slice(0, 500);
    }
  }

  return '';
}

/** Script blobs often use `\u0022` instead of `"` — decode then reuse JSON title patterns. */
function decodeJsUnicodeEscapes(s: string): string {
  return s.replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(Number.parseInt(h, 16)));
}

function extractTitleFromEscapedJson(html: string, itemId: string): string {
  let searchIdx = 0;
  for (let k = 0; k < 8; k++) {
    const idx = html.indexOf(itemId, searchIdx);
    if (idx === -1) break;
    const rawChunk = html.slice(Math.max(0, idx - 14_000), idx + 70_000);
    const chunk = decodeJsUnicodeEscapes(rawChunk);

    const fromStructured = extractEmbeddedListingTitle(chunk, itemId, chunk.slice(0, 55_000));
    if (fromStructured.trim()) return fromStructured;

    const loose = extractFirstMatch(
      chunk,
      /"(?:listingTitle|localizedTitle|seoTitle|primaryTitle|shortTitle)"\s*:\s*"((?:[^"\\]|\\.){16,})"/i,
    );
    if (loose) {
      const t = htmlToText(loose.replace(/\\"/g, '"')).trim();
      if (!isGarbageListingTitle(t) && t.length >= 12) return t.slice(0, 500);
    }

    searchIdx = idx + itemId.length;
  }
  return '';
}

function altLooksLikeListingTitle(s: string): boolean {
  const t = s.trim();
  if (t.length < 18) return false;
  if (/^ebay\s*(logo|basics)?$/i.test(t)) return false;
  if (/^(opens in new window|shop now)$/i.test(t)) return false;
  return true;
}

/** Image-heavy SERPs often put the only human-readable title in `img[alt]` near the listing link. */
function extractTitleFromNearbyImgAlt(win: string): string | null {
  const re = /<img\b[^>]*\balt\s*=\s*["']([^"']+)["'][^>]*>/gi;
  const candidates: string[] = [];
  let mm: RegExpExecArray | null;
  while ((mm = re.exec(win)) !== null) {
    const a = htmlToText(mm[1]).trim();
    if (!altLooksLikeListingTitle(a) || isGarbageListingTitle(a)) continue;
    candidates.push(a);
  }
  if (candidates.length === 0) return null;
  return candidates.sort((a, b) => b.length - a.length)[0].slice(0, 500);
}

/**
 * Fallback when `<li class="s-item">` blocks are missing (layout experiments, different shells).
 * Walk `/itm/<id>` anchors and scrape title/price/sold from a nearby HTML window.
 */
function parseSoldListingsFromItmAnchors(html: string, maxItems: number): any[] {
  const rows: any[] = [];
  const seen = new Set<string>();
  const re = /<a\b[^>]*\bhref\s*=\s*["']([^"']*\/itm\/(\d{8,})[^"']*)["'][^>]*>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null && rows.length < maxItems) {
    const itemId = m[2];
    if (seen.has(itemId)) continue;

    let href = m[1].replace(/&amp;/g, '&');
    const itemWebUrl = href.startsWith('http')
      ? href
      : href.startsWith('//')
      ? `https:${href}`
      : `https://www.ebay.com${href.startsWith('/') ? href : `/${href}`}`;

    const pos = m.index ?? 0;
    const anchorTag = m[0];
    const titleWin = html.slice(Math.max(0, pos - 6_500), pos + 9_000);
    const win = html.slice(Math.max(0, pos - 4_000), pos + 14_000);

    let title = extractListingTitleFromSerpWindow(titleWin, anchorTag);
    if (!title.trim()) {
      title = extractListingTitleFromSerpWindow(win, anchorTag);
    }
    if (!title.trim()) {
      title = titleFromEbayItemUrl(href) ?? titleFromEbayItemUrl(itemWebUrl) ?? '';
    }
    if (!title.trim()) {
      title = extractEmbeddedListingTitle(html, itemId, win);
    }
    if (!title.trim()) {
      title = extractTitleFromEscapedJson(html, itemId);
    }
    if (!title.trim()) {
      const altWin = html.slice(Math.max(0, pos - 14_000), pos + 22_000);
      title = extractTitleFromNearbyImgAlt(altWin) ?? '';
    }

    if (!title.trim()) {
      continue;
    }

    seen.add(itemId);

    let priceInner =
      extractFirstMatch(win, /<span[^>]*class\s*=\s*["'][^"']*s-item__price[^"']*["'][^>]*>([\s\S]*?)<\/span>/i) ?? '';
    let priceText = htmlToText(priceInner);
    if (!priceText) {
      const buck = win.match(/\$\s*[\d,]+\.?\d*/i);
      priceText = htmlToText(buck?.[0] ?? '');
    }
    if (!priceText) {
      priceText = htmlToText(
        extractFirstMatch(win, /itemprop\s*=\s*["']price["'][^>]*content\s*=\s*["']([\d.]+)["']/i) ??
          extractFirstMatch(win, /content\s*=\s*["']([\d.]+)["'][^>]*itemprop\s*=\s*["']price["']/i) ??
          '',
      );
    }

    const soldInner =
      extractFirstMatch(win, /<span[^>]*class\s*=\s*["'][^"']*POSITIVE[^"']*["'][^>]*>([\s\S]*?)<\/span>/i) ?? '';
    let soldLabel = htmlToText(soldInner);
    if (!soldLabel) {
      const soldM = win.match(/\bSold\s+[A-Za-z]{3}\s+\d{1,2},?\s*\d{4}/i);
      soldLabel = htmlToText(soldM?.[0] ?? '');
    }

    const lc = win.toLowerCase();
    const buyingOptions = lc.includes('best offer accepted')
      ? 'best_offer'
      : (lc.includes(' bid') || lc.includes('auction'))
      ? 'auction'
      : 'fixed_price';

    const imageUrl =
      extractFirstMatch(
        win,
        /<img[^>]*class\s*=\s*["'][^"']*s-item__image-img[^"']*["'][^>]*\bsrc\s*=\s*["']([^"']+)["']/i,
      ) ??
      extractFirstMatch(win, /<img[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*class\s*=\s*["'][^"']*s-item__image-img[^"']*["']/i);

    rows.push({
      itemId,
      title,
      price: { value: String(parsePrice(priceText)), currency: 'USD' },
      buyingOptions: resolveSaleType(buyingOptions),
      itemEndDate: parseSoldDate(soldLabel),
      itemWebUrl,
      imageUrl,
    });
  }

  if (rows.length === 0 && /\/itm\/\d{8,}/.test(html)) {
    console.warn(
      '[sold-listings-brightdata] /itm/ links present but no listing titles could be extracted (DOM + slug + embedded JSON)',
    );
  }

  return rows;
}

export function parseSoldListingsFromHtml(html: string, maxItems: number): any[] {
  if (html.includes('data-search-results-fragment') || html.includes('data-sold-result')) {
    const parsed130point = parseSoldListingsFrom130PointHtml(html, maxItems);
    if (parsed130point.length > 0) {
      console.log(`[sold-listings-brightdata] parsed 130point rows=${parsed130point.length}`);
      return parsed130point;
    }
  }

  let itemBlocks = extractSerpItemLiBlocks(html);
  if (itemBlocks.length === 0) {
    const anchorRows = parseSoldListingsFromItmAnchors(html, maxItems);
    if (anchorRows.length > 0) {
      console.log(
        `[sold-listings-brightdata] SERP used /itm/ anchor fallback rows=${anchorRows.length} (no s-item <li> blocks)`,
      );
      return anchorRows;
    }
  }
  return itemBlocks.slice(0, maxItems).map((block: string) => {
    const titleHtml =
      extractFirstMatch(
        block,
        /<div\b[^>]*class\s*=\s*(?:"[^"]*\bs-item__title\b[^"]*"|'[^']*\bs-item__title\b[^']*'|[^\s>]*\bs-item__title\b[^\s>]*)[^>]*>([\s\S]*?)<\/div>/i,
      ) ??
      extractFirstMatch(
        block,
        /<[^>]+class\s*=\s*["'][^"']*\bs-item__title[^"']*["'][^>]*>([\s\S]*?)<\/(?:div|span|h[1-6])>/i,
      ) ??
      extractFirstMatch(block, /<span\b[^>]*role="heading"[^>]*>([\s\S]*?)<\/span>/i) ??
      '';
    const title = htmlToText(titleHtml).replace(/^new listing\s*/i, '');
    const priceText = htmlToText(
      extractFirstMatch(
        block,
        /<span\b[^>]*class\s*=\s*(?:"[^"]*\bs-item__price\b[^"]*"|'[^']*\bs-item__price\b[^']*'|[^\s>]*\bs-item__price\b[^\s>]*)[^>]*>([\s\S]*?)<\/span>/i,
      ) ??
      extractFirstMatch(
        block,
        /<span[^>]*class\s*=\s*["'][^"']*s-item__price[^"']*["'][^>]*>([\s\S]*?)<\/span>/i,
      ) ??
      '',
    );
    const itemWebUrl =
      extractFirstMatch(
        block,
        /<a\b[^>]*class\s*=\s*(?:"[^"]*\bs-item__link\b[^"]*"|'[^']*\bs-item__link\b[^']*'|[^\s>]*\bs-item__link\b[^\s>]*)[^>]*href\s*=\s*["']?([^"' >]+)["']?/i,
      ) ??
      extractFirstMatch(block, /<a\b[^>]*href\s*=\s*["']?([^"' >]*\/itm\/[^"' >]*)["']?/i);
    const soldLabel = htmlToText(
      extractFirstMatch(
        block,
        /<span\b[^>]*class\s*=\s*(?:"[^"]*\bPOSITIVE\b[^"]*"|'[^']*\bPOSITIVE\b[^']*'|[^\s>]*\bPOSITIVE\b[^\s>]*)[^>]*>([\s\S]*?)<\/span>/i,
      ) ?? '',
    );
    const imageUrl =
      extractFirstMatch(
        block,
        /<img\b[^>]*class\s*=\s*(?:"[^"]*\bs-item__image-img\b[^"]*"|'[^']*\bs-item__image-img\b[^']*'|[^\s>]*\bs-item__image-img\b[^\s>]*)[^>]*src\s*=\s*["']?([^"' >]+)["']?/i,
      ) ??
      extractFirstMatch(
        block,
        /<img\b[^>]*class\s*=\s*(?:"[^"]*\bs-item__image-img\b[^"]*"|'[^']*\bs-item__image-img\b[^']*'|[^\s>]*\bs-item__image-img\b[^\s>]*)[^>]*data-src\s*=\s*["']?([^"' >]+)["']?/i,
      );
    const itemId =
      extractFirstMatch(itemWebUrl ?? '', /\/itm\/(\d{8,})/i) ??
      extractFirstMatch(itemWebUrl ?? '', /item=(\d{8,})/i);
    const lc = block.toLowerCase();
    const buyingOptions = lc.includes('best offer accepted')
      ? 'best_offer'
      : (lc.includes(' bid') || lc.includes('auction')) ? 'auction' : 'fixed_price';

    return {
      itemId,
      title,
      price: { value: String(parsePrice(priceText)), currency: 'USD' },
      buyingOptions: resolveSaleType(buyingOptions),
      itemEndDate: parseSoldDate(soldLabel),
      itemWebUrl,
      imageUrl,
    };
  });
}

function parseSoldListingsFrom130PointHtml(html: string, maxItems: number): any[] {
  const rows: any[] = [];
  const seen = new Set<string>();
  const anchors = html.match(/<a\b[^>]*\bdata-sold-result\b[^>]*>[\s\S]*?<\/a>/gi) ?? [];

  for (const block of anchors) {
    if (rows.length >= maxItems) break;

    let href = extractFirstMatch(block, /\bhref\s*=\s*["']([^"']+)["']/i);
    if (!href) continue;
    href = href.replace(/&amp;/g, '&').trim();
    const itemWebUrl = href.startsWith('http')
      ? href
      : href.startsWith('//')
      ? `https:${href}`
      : `https://130point.com${href.startsWith('/') ? href : `/${href}`}`;

    const itemId = extractFirstMatch(itemWebUrl, /\/itm\/(\d{8,})/i) ??
      extractFirstMatch(itemWebUrl, /item=(\d{8,})/i) ??
      extractFirstMatch(itemWebUrl, /\/a(\d{6,})\b/i);
    const dedupeKey = itemId ?? itemWebUrl;
    if (seen.has(dedupeKey)) continue;

    const titleRaw =
      extractFirstMatch(
        block,
        /<p[^>]*class\s*=\s*["'][^"']*line-clamp-2[^"']*["'][^>]*>([\s\S]*?)<\/p>/i,
      ) ??
      extractFirstMatch(block, /<p[^>]*>([\s\S]*?)<\/p>/i) ??
      '';
    const title = htmlToText(titleRaw).trim();
    if (!title || isGarbageListingTitle(title)) continue;

    const priceAmountRaw =
      extractFirstMatch(block, /\bdata-price-amount\s*=\s*["']([^"']+)["']/i) ??
      extractFirstMatch(block, /\bdata-price-display[^>]*>\s*([^<]+)\s*</i) ??
      '';
    const priceValue = parsePrice(priceAmountRaw);
    if (priceValue <= 0) continue;

    const currency =
      extractFirstMatch(block, /\bdata-price-currency\s*=\s*["']([^"']+)["']/i) ??
      'USD';

    const saleTypeLabel = htmlToText(
      extractFirstMatch(
        block,
        /<p[^>]*>\s*(Best Offer Accepted|Auction|Fixed Price)\s*<\/p>/i,
      ) ?? '',
    );
    const buyingOptions = resolveSaleType(saleTypeLabel || 'fixed_price');

    const itemEndDate = extractFirstMatch(block, /\bdata-result-end-time\s*=\s*["']([^"']+)["']/i);

    const imageUrl = extractFirstMatch(
      block,
      /<img[^>]*\bsrc\s*=\s*["'](https?:\/\/[^"']+)["'][^>]*>/i,
    );

    seen.add(dedupeKey);
    rows.push({
      itemId,
      title,
      price: { value: String(priceValue), currency },
      buyingOptions,
      itemEndDate: itemEndDate ?? null,
      itemWebUrl,
      imageUrl,
    });
  }

  return rows;
}

export function soldRefreshRowsToSearchShape(rows: any[]) {
  return rows.map((r: any) => ({
    itemId: r.itemId ?? null,
    title: r.title ?? '',
    price: Number.parseFloat(r.price?.value ?? '0'),
    currency: r.price?.currency ?? 'USD',
    sale_type: typeof r.buyingOptions === 'string' ? r.buyingOptions : 'fixed_price',
    sold_at: r.itemEndDate ?? null,
    url: r.itemWebUrl ?? null,
    image_url: r.imageUrl ?? null,
  }));
}

function sold130PointSearchUrl(query: string): string {
  return `https://130point.com/api/search/html?q=${encodeURIComponent(query)}&sort=recent&mp=all`;
}

function normalizeListingUrl(url: string | null | undefined): string | null {
  if (!url || typeof url !== 'string') return null;
  const t = url.trim();
  if (!t.startsWith('http')) return `https:${t.startsWith('//') ? '' : '//'}${t}`;
  return t;
}

/**
 * Extract final sold price from an eBay item (ended listing) HTML.
 * Tries structured JSON (including sales_price), ld+json, then visible US $ price.
 */
export function extractSoldPriceFromEbayListingHtml(html: string): number | null {
  if (isEbaySecurityPage(html)) return null;

  const salesPriceQuoted = html.match(/"sales_price"\s*:\s*"?([\d.]+)"?/i) ??
    html.match(/sales_price["']?\s*[:=]\s*([\d.]+)/i);
  if (salesPriceQuoted) {
    const v = parsePrice(salesPriceQuoted[1]);
    if (v > 0) return v;
  }

  const ldIter = html.matchAll(
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  );
  for (const m of ldIter) {
    try {
      const raw = m[1].trim();
      if (!raw) continue;
      const j = JSON.parse(raw);
      const nodes = Array.isArray(j) ? j : [j];
      for (const node of nodes) {
        const offer = node?.offers;
        const offers = Array.isArray(offer) ? offer : offer ? [offer] : [];
        for (const o of offers) {
          const p = o?.price ?? o?.priceSpecification?.price;
          if (p != null) {
            const v = parsePrice(p);
            if (v > 0) return v;
          }
        }
        const direct = node?.price;
        if (direct != null) {
          const v = parsePrice(direct);
          if (v > 0) return v;
        }
      }
    } catch {
      /* next block */
    }
  }

  const usPrice = html.match(/US\s*\$\s*([\d,]+\.?\d*)/i) ??
    html.match(/\$\s*([\d,]+\.?\d*)\s*(?:USD|us\s*d)/i);
  if (usPrice) {
    const v = parsePrice(usPrice[1]);
    if (v > 0) return v;
  }

  const winning = html.match(/(?:winning\s+bid|sold\s+for)\s*:?\s*\$?\s*([\d,]+\.?\d*)/i);
  if (winning) {
    const v = parsePrice(winning[1]);
    if (v > 0) return v;
  }

  return null;
}

function unlockTimeoutMs(kind: 'search' | 'listing'): number {
  const legacy = Deno.env.get('BRIGHTDATA_TIMEOUT_MS');
  if (legacy != null && legacy !== '') {
    return Number(legacy);
  }
  if (kind === 'search') {
    const v = Deno.env.get('BRIGHTDATA_SEARCH_TIMEOUT_MS');
    return v != null && v !== '' ? Number(v) : DEFAULT_SEARCH_TIMEOUT_MS;
  }
  const v = Deno.env.get('BRIGHTDATA_LISTING_TIMEOUT_MS');
  return v != null && v !== '' ? Number(v) : DEFAULT_LISTING_TIMEOUT_MS;
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: c.signal });
  } finally {
    clearTimeout(t);
  }
}

/**
 * Bright Data error/dashboard responses are HTML. Real unlock results are usually JSON with a `body` string;
 * occasionally Bright Data returns raw target HTML instead — use `isLikelyRawUnlockedEbayHtml` before calling this.
 */
function throwIfBrightDataReturnedHtml(
  text: string,
  where: string,
  httpStatus: number,
  contentType: string | null,
): void {
  const raw = text.trimStart();
  const head = raw.slice(0, 512).toLowerCase();
  if (!head.startsWith('<!doctype') && !head.startsWith('<html') && !head.startsWith('<head')) return;

  const titleMatch = raw.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  const title = (titleMatch?.[1] ?? '').replace(/\s+/g, ' ').trim().slice(0, 120);

  let hint: string;
  if (where === 'sync_body') {
    hint =
      'POST /request got HTML, not JSON. Fix: copy API key from Bright Data → Account settings → API keys (create a new key if unsure). BRIGHTDATA_UNLOCKER_ZONE must match the Web Unlocker zone name exactly (Zones list). Check billing/trial and that Web Unlocker is active. CUSTOMER_ID does not apply to this endpoint.';
  } else if (where === 'submit' || where.startsWith('poll')) {
    hint =
      'Async /unblocker/* returned HTML. Check API key + zone; set BRIGHTDATA_PROXY_USERNAME or CUSTOMER_ID; enable Asynchronous requests on the zone.';
  } else {
    hint = 'Bright Data returned HTML instead of JSON.';
  }

  console.warn(
    `[sold-listings-brightdata] api_returned_html where=${where} http=${httpStatus} content_type=${contentType ?? 'unset'} title=${title || '(none)'}`,
  );

  throw new Error(
    `brightdata_api_html:${where}:http=${httpStatus}${title ? `:title=${title}` : ''}: ${hint} Snippet:${raw.slice(0, 140)}`,
  );
}

/**
 * Async Unlocker flow (Bright Data docs): POST /unblocker/req → poll /unblocker/get_result.
 * Requires “Asynchronous requests” enabled on the Unlocker zone (dashboard Advanced settings).
 */
async function unlockViaAsyncPoll(targetUrl: string, label: string): Promise<string> {
  const ctx = resolveBrightDataUnlockerContext();
  const { apiKey, zone, customer, ctxSource } = ctx;
  if (!apiKey || !zone) {
    throw new Error('brightdata_not_configured');
  }
  if (!customer) {
    throw new Error(
      'brightdata_async_missing_customer: Set BRIGHTDATA_PROXY_USERNAME to your full proxy user from Unlocker Access details (brd-customer-…-zone-…) or set BRIGHTDATA_CUSTOMER_ID',
    );
  }

  console.log(
    `[sold-listings-brightdata] unlocker ctx source=${ctxSource} zone="${zone}" customer_len=${customer.length}`,
  );
  const checkEbaySecurity = shouldCheckEbaySecurity(targetUrl);

  const maxPollMs = Number(Deno.env.get('BRIGHTDATA_ASYNC_POLL_MAX_MS') ?? String(DEFAULT_ASYNC_POLL_MAX_MS));
  const pollEveryMs = Number(Deno.env.get('BRIGHTDATA_ASYNC_POLL_INTERVAL_MS') ?? String(DEFAULT_ASYNC_POLL_INTERVAL_MS));
  const httpMs = Number(Deno.env.get('BRIGHTDATA_ASYNC_HTTP_TIMEOUT_MS') ?? String(DEFAULT_ASYNC_HTTP_MS));

  const submitParams = new URLSearchParams({ zone });
  if (customer) submitParams.set('customer', customer);

  const submitUrl = `${BRIGHTDATA_UNBLOCKER_REQ_URL}?${submitParams}`;
  const host = (() => {
    try {
      return new URL(targetUrl).hostname;
    } catch {
      return '?';
    }
  })();

  console.log(`[sold-listings-brightdata] async submit label=${label} target_host=${host}`);

  let submitRes: Response;
  try {
    submitRes = await fetchWithTimeout(
      submitUrl,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({ url: targetUrl, method: 'GET' }),
      },
      httpMs,
    );
  } catch (e: unknown) {
    rethrowAsyncFetchError(e);
  }

  const submitText = await submitRes.text();
  throwIfBrightDataReturnedHtml(submitText, 'submit', submitRes.status, submitRes.headers.get('content-type'));

  let submitJson: Record<string, unknown>;
  try {
    submitJson = JSON.parse(submitText) as Record<string, unknown>;
  } catch {
    throw new Error(`brightdata_async_submit_failed: non-json status=${submitRes.status} body=${submitText.slice(0, 280)}`);
  }

  if (!submitRes.ok) {
    throw new Error(
      `brightdata_async_submit_failed: http=${submitRes.status} ${JSON.stringify(submitJson).slice(0, 500)}`,
    );
  }

  const responseId = submitJson.response_id;
  if (typeof responseId !== 'string' || responseId.length === 0) {
    throw new Error(`brightdata_async_no_response_id: ${JSON.stringify(submitJson).slice(0, 400)}`);
  }

  console.log(`[sold-listings-brightdata] async response_id=${responseId.slice(0, 12)}… poll_max_ms=${maxPollMs}`);

  const deadline = Date.now() + maxPollMs;
  const pollStarted = Date.now();
  let pendingPolls = 0;

  while (Date.now() < deadline) {
    const resultParams = new URLSearchParams({
      response_id: responseId,
      zone,
    });
    if (customer) resultParams.set('customer', customer);

    const resultUrl = `${BRIGHTDATA_UNBLOCKER_GET_RESULT_URL}?${resultParams}`;

    let pollRes: Response;
    try {
      pollRes = await fetchWithTimeout(
        resultUrl,
        {
          headers: {
            Authorization: `Bearer ${apiKey}`,
            Accept: 'application/json',
          },
        },
        httpMs,
      );
    } catch (e: unknown) {
      rethrowAsyncFetchError(e);
    }

    const pollText = await pollRes.text();

    if (pollRes.status === 202) {
      pendingPolls++;
      const elapsed = Date.now() - pollStarted;
      console.log(
        `[sold-listings-brightdata] async poll pending label=${label} n=${pendingPolls} elapsed_ms=${elapsed}`,
      );
      await sleep(pollEveryMs);
      continue;
    }

    if (!pollRes.ok) {
      throwIfBrightDataReturnedHtml(pollText, 'poll_error', pollRes.status, pollRes.headers.get('content-type'));
      throw new Error(`brightdata_async_poll_failed: http=${pollRes.status} body=${pollText.slice(0, 400)}`);
    }

    let pollData: Record<string, unknown> | null = null;
    try {
      pollData = JSON.parse(pollText) as Record<string, unknown>;
    } catch {
      pollData = null;
    }

    if (pollData === null) {
      if (isLikelyRawUnlockedEbayHtml(pollText)) {
        console.log('[sold-listings-brightdata] async poll returned raw eBay HTML (no JSON envelope)');
        if (checkEbaySecurity && isEbaySecurityPage(pollText)) {
          throw new Error('ebay_bot_protection_page');
        }
        console.log(`[sold-listings-brightdata] async unlock ok label=${label} html_bytes=${pollText.length}`);
        return pollText;
      }
      throwIfBrightDataReturnedHtml(pollText, 'poll_body', pollRes.status, pollRes.headers.get('content-type'));
      throw new Error(`brightdata_async_poll_non_json: ${pollText.slice(0, 240)}`);
    }

    const data = pollData;
    const statusCode = Number(data.status_code ?? pollRes.status);
    if (statusCode >= 400) {
      throw new Error(`brightdata_async_bad_status: ${statusCode}`);
    }

    const body = data.body;
    const html = typeof body === 'string' ? body : '';
    if (!html) {
      console.warn(`[sold-listings-brightdata] async empty body keys=${Object.keys(data).join(',')}`);
      throw new Error('brightdata_empty_body');
    }

    if (checkEbaySecurity && isEbaySecurityPage(html)) {
      throw new Error('ebay_bot_protection_page');
    }

    console.log(`[sold-listings-brightdata] async unlock ok label=${label} html_bytes=${html.length}`);
    return html;
  }

  const elapsedMs = Date.now() - pollStarted;
  throw new Error(
    `brightdata_async_poll_exhausted: still HTTP 202 pending after ${pendingPolls} polls, ${elapsedMs}ms (limit ${maxPollMs}ms). Set BRIGHTDATA_ASYNC_POLL_MAX_MS higher if your Edge runtime allows, or check Bright Data zone/job limits.`,
  );
}

function rethrowAsyncFetchError(e: unknown): never {
  if ((e as { name?: string }).name === 'AbortError') {
    throw new Error('brightdata_async_http_timeout');
  }
  throw e;
}

async function brightDataUnlockSync(
  targetUrl: string,
  label: string,
  kind: 'search' | 'listing',
): Promise<string> {
  const ctx = resolveBrightDataUnlockerContext();
  const { apiKey, zone } = ctx;
  if (!apiKey || !zone) {
    throw new Error('brightdata_not_configured');
  }

  const timeoutMs = unlockTimeoutMs(kind);
  const checkEbaySecurity = shouldCheckEbaySecurity(targetUrl);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    console.log(
      `[sold-listings-brightdata] sync POST ${BRIGHTDATA_REQUEST_URL} label=${label} timeout_ms=${timeoutMs} target_host=${
        (() => {
          try {
            return new URL(targetUrl).hostname;
          } catch {
            return '?';
          }
        })()
      } api_key_len=${apiKey.length} zone="${zone}"`,
    );

    const res = await fetch(BRIGHTDATA_REQUEST_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        zone,
        url: targetUrl,
        format: 'json',
        method: 'GET',
      }),
      signal: controller.signal,
    });

    const text = await res.text();
    const contentType = res.headers.get('content-type');

    let data: Record<string, unknown> | null = null;
    try {
      data = JSON.parse(text) as Record<string, unknown>;
    } catch {
      data = null;
    }

    if (data === null) {
      if (isLikelyRawUnlockedEbayHtml(text)) {
        console.log('[sold-listings-brightdata] sync POST /request returned raw eBay HTML (no JSON envelope)');
        if (checkEbaySecurity && isEbaySecurityPage(text)) {
          throw new Error('ebay_bot_protection_page');
        }
        console.log(
          `[sold-listings-brightdata] sync unlock ok label=${label} html_bytes=${text.length} http_status=${res.status}`,
        );
        return text;
      }
      throwIfBrightDataReturnedHtml(text, 'sync_body', res.status, contentType);
      throw new Error(`brightdata_unlock_failed: non-json status=${res.status} body=${text.slice(0, 240)}`);
    }

    if (!res.ok) {
      throw new Error(
        `brightdata_unlock_failed: http=${res.status} ${JSON.stringify(data).slice(0, 400)}`,
      );
    }

    const statusCode = Number(data?.status_code ?? res.status);
    if (statusCode >= 400) {
      throw new Error(`brightdata_unlock_failed: status_code=${statusCode}`);
    }

    const body = data?.body;
    const html = typeof body === 'string' ? body : '';
    if (!html) {
      console.warn(`[sold-listings-brightdata] empty html (${label}) keys=${Object.keys(data).join(',')}`);
      throw new Error('brightdata_empty_body');
    }

    if (checkEbaySecurity && isEbaySecurityPage(html)) {
      throw new Error('ebay_bot_protection_page');
    }

    console.log(`[sold-listings-brightdata] sync unlock ok label=${label} html_bytes=${html.length} http_status=${res.status}`);

    return html;
  } catch (e: unknown) {
    if ((e as { name?: string })?.name === 'AbortError') {
      throw new Error('brightdata_timeout');
    }
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

function shouldFallbackSyncFromAsyncError(msg: string): boolean {
  if (Deno.env.get('BRIGHTDATA_ASYNC_FALLBACK_SYNC') === 'false') return false;
  return msg.includes('brightdata_api_html') ||
    msg.includes('brightdata_async_api_html') ||
    msg.includes('brightdata_async_poll_exhausted') ||
    msg.includes('brightdata_async_submit_failed');
}

function is130PointTarget(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return host === '130point.com' || host.endsWith('.130point.com');
  } catch {
    return false;
  }
}

async function brightDataUnlockHtml(
  targetUrl: string,
  label: string,
  kind: 'search' | 'listing',
): Promise<string> {
  const ctx = resolveBrightDataUnlockerContext();
  const { apiKey, zone, customer } = ctx;
  if (!apiKey || !zone) {
    throw new Error('brightdata_not_configured');
  }

  const forceSync = Deno.env.get('BRIGHTDATA_SYNC_UNLOCK') === 'true';
  const allow130PointAsync = Deno.env.get('BRIGHTDATA_130POINT_ALLOW_ASYNC') === 'true';
  const preferSyncFor130Point = is130PointTarget(targetUrl) && !allow130PointAsync;

  // Always use Bright Data Unlocker (no direct GET to 130point — matches comps reliability).

  // Sync API only needs zone + API key—no customer param.
  // Prefer sync when forced, customer is missing, or for 130point (async queue can add large latency).
  if (forceSync || !customer || preferSyncFor130Point) {
    if (preferSyncFor130Point && !forceSync) {
      console.log('[sold-listings-brightdata] 130point target detected — using sync POST /request (set BRIGHTDATA_130POINT_ALLOW_ASYNC=true to override)');
    }
    if (!customer && !forceSync) {
      console.log(
        '[sold-listings-brightdata] no BRIGHTDATA_CUSTOMER_ID / PROXY_USERNAME — using sync POST /request only',
      );
    }
    return await brightDataUnlockSync(targetUrl, label, kind);
  }

  try {
    return await unlockViaAsyncPoll(targetUrl, label);
  } catch (e: unknown) {
    const msg = String((e as Error)?.message ?? e ?? '');
    if (shouldFallbackSyncFromAsyncError(msg)) {
      console.warn(
        `[sold-listings-brightdata] async unlock failed; falling back to sync (${msg.slice(0, 160)})`,
      );
      return await brightDataUnlockSync(targetUrl, label, kind);
    }
    throw e;
  }
}

async function sleep(ms: number): Promise<void> {
  await new Promise(r => setTimeout(r, ms));
}

/**
 * Primary entry: Bright Data Unlocker on eBay sold search, parse up to 80 items.
 * BOA listing-page unlocks run only when BRIGHTDATA_MAX_BO_DETAIL_FETCHES is set above 0 (default off).
 */
export async function fetchSoldListingsBrightData(query: string): Promise<any[]> {
  const lookbackDays = soldLookbackDays();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - lookbackDays);

  const ctx = resolveBrightDataUnlockerContext();
  if (!ctx.apiKey || !ctx.zone) throw new Error('brightdata_not_configured');

  const envSerp = Number(Deno.env.get('BRIGHTDATA_MAX_SEARCH_ITEMS') ?? String(BRIGHTDATA_MAX_SERP_ITEMS));
  const maxSerpItems = Math.min(BRIGHTDATA_MAX_SERP_ITEMS, Math.max(1, envSerp));
  const maxBoDetails = Math.max(
    0,
    Number(Deno.env.get('BRIGHTDATA_MAX_BO_DETAIL_FETCHES') ?? String(DEFAULT_MAX_BO_DETAIL)),
  );

  const ebayUrl = sold130PointSearchUrl(query);
  let sourceItems: any[] = [];

  console.log(`[sold-listings-brightdata] fetch start query_len=${query.length} max_serp=${maxSerpItems}`);

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const html = await brightDataUnlockHtml(ebayUrl, 'search', 'search');
      try {
        sourceItems = parseSoldListingsFromHtml(html, maxSerpItems);
      } catch (parseErr: unknown) {
        console.error('[sold-listings-brightdata] parseSoldListingsFromHtml failed:', parseErr);
        throw new Error(`brightdata_parse_failed: ${String((parseErr as Error)?.message ?? parseErr)}`);
      }
      if (sourceItems.length === 0) {
        const markers = (html.match(/\bs-item\b/gi) ?? []).length;
        const itms = (html.match(/\/itm\/\d{8,}/g) ?? []).length;
        console.warn(
          `[sold-listings-brightdata] SERP parse 0 cards html_bytes=${html.length} s_item_markers=${markers} itm_paths=${itms} no_exact_match_banner=${html.includes('No exact matches found')}`,
        );
      }
      break;
    } catch (e: unknown) {
      const msg = String((e as { message?: string })?.message ?? e ?? '');
      if (msg.includes('ebay_bot_protection_page')) {
        const retryBot =
          Deno.env.get('BRIGHTDATA_RETRY_ON_EBAY_BOT') === 'true' ||
          Deno.env.get('BRIGHTDATA_RETRY_ON_EBAY_BOT') === '1';
        if (retryBot && attempt < MAX_RETRIES) {
          const msRaw = Number(Deno.env.get('BRIGHTDATA_EBAY_BOT_RETRY_MS') ?? '6000');
          const ms = Math.min(30_000, Math.max(1_000, Number.isFinite(msRaw) ? msRaw : 6000));
          console.warn(
            `[sold-listings-brightdata] ebay_bot_protection_page — retry in ${ms}ms (${attempt}/${MAX_RETRIES})`,
          );
          await sleep(ms);
          continue;
        }
        throw e;
      }
      // Retrying a timed-out Unlocker call doubles wall-clock (bad for Edge limits); fail fast.
      if (msg.includes('brightdata_timeout')) throw e;
      if (msg.includes('brightdata_api_html')) throw e;
      if (msg.includes('brightdata_async_')) throw e;
      if (attempt === MAX_RETRIES) throw e;
      await sleep(RETRY_BASE_MS * Math.pow(2, attempt - 1));
    }
  }

  const mapped = sourceItems
    .map((p: any) => {
      const rawPrice =
        p.price && typeof p.price === 'object' && 'value' in p.price
          ? (p.price as { value: unknown }).value
          : (p.price ?? p.priceText);
      const priceValue = parsePrice(rawPrice);
      return {
        itemId: p.itemId ?? null,
        title: p.title ?? '',
        price: { value: String(priceValue), currency: p.currency ?? 'USD' },
        buyingOptions: resolveSaleType(p.buyingOptions ?? null),
        itemEndDate: p.itemEndDate ?? null,
        itemWebUrl: p.itemWebUrl ?? null,
        imageUrl: p.imageUrl ?? null,
      };
    })
    .filter((item: any) => item.title && Number.parseFloat(item.price.value) > 0)
    .filter((item: any) => !item.itemEndDate || new Date(item.itemEndDate) >= cutoff);

  if (sourceItems.length > 0 && mapped.length === 0) {
    const s0 = sourceItems[0] as any;
    const rawPrice =
      s0?.price && typeof s0.price === 'object' && 'value' in s0.price
        ? (s0.price as { value: unknown }).value
        : (s0?.price ?? s0?.priceText);
    const parsedPrice = parsePrice(rawPrice);
    const soldDate = s0?.itemEndDate ? new Date(String(s0.itemEndDate)) : null;
    const dateDropped =
      soldDate != null && Number.isFinite(soldDate.getTime()) && soldDate < cutoff;
    console.warn(
      `[sold-listings-brightdata] price/date filters dropped all parsed rows (n=${sourceItems.length}); lookback_days=${lookbackDays} cutoff=${cutoff.toISOString().slice(0, 10)} ` +
        `sample_price_parsed=${parsedPrice} date_before_cutoff=${dateDropped} ` +
        `title=${String(s0?.title ?? '').slice(0, 80)} sold_raw=${s0?.itemEndDate ?? ''}`,
    );
  }

  if (maxBoDetails <= 0) {
    console.log('[sold-listings-brightdata] listing_detail unlocks skipped (BO enrichment off; max=0)');
    return mapped;
  }

  const boRows: { row: any; url: string }[] = [];
  for (const row of mapped) {
    if (row.buyingOptions !== 'best_offer') continue;
    const u = normalizeListingUrl(row.itemWebUrl);
    if (u) boRows.push({ row, url: u });
  }

  const limitedBo = boRows.slice(0, maxBoDetails);
  console.log(
    `[sold-listings-brightdata] boa_candidates=${boRows.length} detail_unlocks=${limitedBo.length} (cap=${maxBoDetails})`,
  );

  for (let i = 0; i < limitedBo.length; i += BO_DETAIL_CONCURRENCY) {
    const chunk = limitedBo.slice(i, i + BO_DETAIL_CONCURRENCY);
    await Promise.all(
      chunk.map(async ({ row, url }) => {
        try {
          const detailHtml = await brightDataUnlockHtml(url, 'listing_detail', 'listing');
          const sold = extractSoldPriceFromEbayListingHtml(detailHtml);
          if (sold != null && sold > 0) {
            row.price = { value: String(sold), currency: 'USD' };
          }
        } catch (err: unknown) {
          console.warn(
            `[sold-listings-brightdata] listing_detail failed item=${row.itemId ?? '?'}:`,
            String((err as { message?: string })?.message ?? err),
          );
        }
      }),
    );
    if (i + BO_DETAIL_CONCURRENCY < limitedBo.length) {
      await sleep(BO_DETAIL_BATCH_DELAY_MS);
    }
  }

  return mapped;
}
