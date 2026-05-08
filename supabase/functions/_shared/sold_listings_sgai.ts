/**
 * Sold listings via ScrapeGraphAI scraping eBay completed search HTML.
 */

const SCRAPEGRAPH_SCRAPE_URL = 'https://v2-api.scrapegraphai.com/api/scrape';
const DECODO_SCRAPER_URL = 'https://scraper-api.decodo.com/v2/scrape';
const LOOKBACK_DAYS = 90;
const MAX_RETRIES = 2;
const RETRY_BASE_MS = 800;

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

type ScrapeProfile = {
  name: 'js-primary';
  maxItems: number;
  waitMs: number;
  timeoutMs: number;
  mode: 'auto' | 'fast' | 'js';
  stealth: boolean;
};

const JS_PRIMARY_PROFILE: ScrapeProfile = {
  name: 'js-primary',
  maxItems: 40,
  waitMs: 900,
  timeoutMs: 14000,
  mode: 'js',
  stealth: true,
};

function isRetryableError(error: unknown): boolean {
  const msg = String((error as any)?.message ?? error ?? '').toLowerCase();
  return msg.includes('429') ||
    msg.includes('5') ||
    msg.includes('json parse error') ||
    msg.includes('timed out') ||
    msg.includes('timeout') ||
    msg.includes('temporarily unavailable');
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

function extractHtmlFromScrapeGraphResponse(data: any): string {
  const candidates: unknown[] = [
    data?.results?.html?.data,
    data?.results?.html,
    data?.results?.markdown?.data,
    data?.results?.markdown,
    data?.result?.html?.data,
    data?.result?.html,
    data?.data?.html,
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      const joined = candidate
        .filter((part): part is string => typeof part === 'string')
        .join('\n');
      if (joined.length > 0) return joined;
    }
    if (typeof candidate === 'string' && candidate.length > 0) return candidate;
  }
  return '';
}

function extractHtmlFromDecodoResponse(data: any): string {
  const candidates: unknown[] = [
    data?.results?.[0]?.content,
    data?.results?.[0]?.html,
    data?.result?.content,
    data?.result?.html,
    data?.content,
    data?.html,
    data?.data?.content,
    data?.data?.html,
  ];
  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      const joined = candidate
        .filter((part): part is string => typeof part === 'string')
        .join('\n');
      if (joined.length > 0) return joined;
    }
    if (typeof candidate === 'string' && candidate.length > 0) return candidate;
  }
  return '';
}

async function fetchDecodoTaskResultHtml(
  taskId: string,
  authValue: string,
  timeoutMs: number,
): Promise<string> {
  const resultsUrl = `https://scraper-api.decodo.com/v3/task/${encodeURIComponent(taskId)}/results`;
  const startedAt = Date.now();
  const maxPolls = 8;

  for (let poll = 1; poll <= maxPolls; poll++) {
    const elapsed = Date.now() - startedAt;
    if (elapsed > timeoutMs) break;

    const res = await fetch(resultsUrl, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        Authorization: `Basic ${authValue}`,
      },
    });

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`decodo task_results ${res.status}: ${body}`);
    }

    const data = await res.json();
    const html = extractHtmlFromDecodoResponse(data);
    if (html) return html;

    const status = String(data?.status ?? data?.results?.[0]?.status ?? '').toLowerCase();
    if (status.includes('failed') || status.includes('error')) {
      throw new Error(`decodo task_failed: ${JSON.stringify(data).slice(0, 500)}`);
    }

    const waitMs = Math.min(5000, 800 * poll);
    await new Promise(r => setTimeout(r, waitMs));
  }

  return '';
}

function isEbaySecurityPage(html: string): boolean {
  const t = html.toLowerCase();
  return t.includes('<title>security measure') ||
    t.includes('captcha') ||
    t.includes('robot check') ||
    t.includes('verify you are human') ||
    t.includes('pardon our interruption') ||
    t.includes('automated access to ebay') ||
    t.includes('access denied') ||
    t.includes('please enable js and disable any ad blocker');
}

function parseSoldListingsFromHtml(html: string, maxItems: number): any[] {
  const itemBlocks = html.match(/<li\b[^>]*class="[^"]*\bs-item\b[^"]*"[^>]*>[\s\S]*?<\/li>/gi) ?? [];
  return itemBlocks.slice(0, maxItems).map((block: string) => {
    const titleHtml =
      extractFirstMatch(block, /<div\b[^>]*class="[^"]*\bs-item__title\b[^"]*"[^>]*>([\s\S]*?)<\/div>/i) ??
      extractFirstMatch(block, /<span\b[^>]*role="heading"[^>]*>([\s\S]*?)<\/span>/i) ??
      '';
    const title = htmlToText(titleHtml).replace(/^new listing\s*/i, '');
    const priceText = htmlToText(
      extractFirstMatch(block, /<span\b[^>]*class="[^"]*\bs-item__price\b[^"]*"[^>]*>([\s\S]*?)<\/span>/i) ?? '',
    );
    const itemWebUrl =
      extractFirstMatch(block, /<a\b[^>]*class="[^"]*\bs-item__link\b[^"]*"[^>]*href="([^"]+)"/i) ??
      extractFirstMatch(block, /<a\b[^>]*href="([^"]+\/itm\/[^"]+)"/i);
    const soldLabel = htmlToText(
      extractFirstMatch(block, /<span\b[^>]*class="[^"]*\bPOSITIVE\b[^"]*"[^>]*>([\s\S]*?)<\/span>/i) ?? '',
    );
    const imageUrl =
      extractFirstMatch(block, /<img\b[^>]*class="[^"]*\bs-item__image-img\b[^"]*"[^>]*src="([^"]+)"/i) ??
      extractFirstMatch(block, /<img\b[^>]*class="[^"]*\bs-item__image-img\b[^"]*"[^>]*data-src="([^"]+)"/i);
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

/**
 * Rows used by refresh-comps (parseAndFilter + DB inserts).
 */
export async function fetchSoldListingsScrapingBee(query: string): Promise<any[]> {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);
  const apiKey = Deno.env.get('SGAI_API_KEY');
  if (!apiKey) throw new Error('Missing SGAI_API_KEY');
  const ebayUrl =
    `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(query)}&LH_Sold=1&LH_Complete=1&_sop=13&rt=nc`;

  async function requestWithProfile(profile: ScrapeProfile): Promise<any[]> {
    const res = await fetch(SCRAPEGRAPH_SCRAPE_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'SGAI-APIKEY': apiKey,
      },
      body: JSON.stringify({
      url: ebayUrl,
        formats: [
          {
            type: 'html',
            mode: 'prune',
          },
        ],
        fetchConfig: {
          mode: profile.mode,
          stealth: profile.stealth,
          wait: profile.waitMs,
          timeout: profile.timeoutMs,
        },
      }),
    });
    if (!res.ok) throw new Error(`scrapegraphai ${res.status}: ${await res.text()}`);
    const data = await res.json();
    const html = extractHtmlFromScrapeGraphResponse(data);
    if (!html) return [];
    if (isEbaySecurityPage(html)) {
      throw new Error('ebay_bot_protection_page');
    }
    return parseSoldListingsFromHtml(html, profile.maxItems);
  }

  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      let sourceItems: any[] = [];
      let lastError: unknown = null;
      let hadSuccessfulResponse = false;
      const profiles: ScrapeProfile[] = [JS_PRIMARY_PROFILE];

      for (const profile of profiles) {
        try {
          sourceItems = await requestWithProfile(profile);
          // Stop immediately after the first successful provider response.
          // Even if parsed items are empty, do not fan out into more retries.
          hadSuccessfulResponse = true;
          break;
        } catch (profileError) {
          lastError = profileError;
          // Keep stepping down profiles for parse/timeout or transient scrape issues.
          if (!isRetryableError(profileError)) {
            console.log(`[sold-listings-sgai] profile ${profile.name} failed:`, String((profileError as any)?.message ?? profileError));
          }
          continue;
        }
      }

      if (hadSuccessfulResponse) {
        return sourceItems
          .map((p: any) => {
            const priceValue = parsePrice(p.price ?? p.priceText);
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
      }

      if (sourceItems.length === 0 && lastError) {
        throw lastError;
      }
    } catch (e: any) {
      const msg = String(e?.message ?? e ?? '');
      if (msg.includes('ebay_bot_protection_page')) throw e;
      if (attempt === MAX_RETRIES) throw e;
      await new Promise(r => setTimeout(r, RETRY_BASE_MS * Math.pow(2, attempt - 1)));
    }
  }
  return [];
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

function normalizeProviderItems(rows: any[]): any[] {
  return rows
    .map((p: any) => {
      const priceValue = parsePrice(
        p?.price?.value ??
        p?.price ??
        p?.priceText ??
        p?.amount,
      );
      return {
        itemId: p?.itemId ?? null,
        title: p?.title ?? '',
        price: { value: String(priceValue), currency: p?.currency ?? p?.price?.currency ?? 'USD' },
        buyingOptions: resolveSaleType(p?.buyingOptions ?? p?.sale_type ?? null),
        itemEndDate: p?.itemEndDate ?? p?.soldDate ?? p?.sold_at ?? null,
        itemWebUrl: p?.itemWebUrl ?? p?.url ?? null,
        imageUrl: p?.imageUrl ?? p?.image_url ?? null,
      };
    })
    .filter((item: any) => item.title && Number.parseFloat(item.price.value) > 0);
}

export async function fetchSoldListingsSelfHosted(query: string): Promise<any[]> {
  const endpoint = Deno.env.get('SELF_HOSTED_SCRAPER_URL');
  if (!endpoint) throw new Error('self_hosted_not_configured');

  const apiKey = Deno.env.get('SELF_HOSTED_SCRAPER_API_KEY') ?? '';
  const timeoutMs = Number(Deno.env.get('SELF_HOSTED_TIMEOUT_MS') ?? '90000');
  const maxItems = Number(Deno.env.get('SELF_HOSTED_MAX_ITEMS') ?? '40');
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(apiKey ? { 'x-api-key': apiKey } : {}),
      },
      body: JSON.stringify({ query, maxItems }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`self_hosted ${res.status}: ${body}`);
    }

    const payload = await res.json();
    const rows = Array.isArray(payload) ? payload : Array.isArray(payload?.items) ? payload.items : [];
    const normalized = normalizeProviderItems(rows);
    return normalized.filter((item: any) => !item.itemEndDate || new Date(item.itemEndDate) >= cutoff);
  } catch (error: any) {
    if (error?.name === 'AbortError') {
      throw new Error('self_hosted_timeout');
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

export async function fetchSoldListingsDecodo(query: string): Promise<any[]> {
  const username = Deno.env.get('DECODO_SCRAPER_USERNAME') ?? '';
  const password = Deno.env.get('DECODO_SCRAPER_PASSWORD') ?? '';
  const token = Deno.env.get('DECODO_SCRAPER_TOKEN') ?? '';
  if ((!username || !password) && !token) throw new Error('decodo_not_configured');

  const endpoint = Deno.env.get('DECODO_SCRAPER_URL') ?? DECODO_SCRAPER_URL;
  const timeoutMs = Number(Deno.env.get('DECODO_SCRAPER_TIMEOUT_MS') ?? '90000');
  const maxItems = Number(Deno.env.get('DECODO_SCRAPER_MAX_ITEMS') ?? '40');
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);

  const ebayUrl =
    `https://www.ebay.com/sch/i.html?_nkw=${encodeURIComponent(query)}&LH_Sold=1&LH_Complete=1&_sop=13&rt=nc`;
  const authValue = token
    ? token
    : btoa(`${username}:${password}`);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Accept: 'application/json',
          Authorization: `Basic ${authValue}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          url: ebayUrl,
        }),
        signal: controller.signal,
      });

      if (!res.ok) {
        const body = await res.text();
        if (attempt === MAX_RETRIES) throw new Error(`decodo ${res.status}: ${body}`);
        await new Promise(r => setTimeout(r, RETRY_BASE_MS * Math.pow(2, attempt - 1)));
        continue;
      }

      const data = await res.json();
      let html = extractHtmlFromDecodoResponse(data);
      if (!html && typeof data?.task_id === 'string' && data.task_id.length > 0) {
        const status = String(data?.status ?? '').toLowerCase();
        const statusCode = Number(data?.status_code ?? 0);
        if (status.includes('failed') || statusCode === 613) {
          console.warn('[sold-listings-decodo] async task failed before results poll', {
            taskId: data.task_id,
            status,
            statusCode,
            message: data?.message ?? null,
            query,
          });
          throw new Error('ebay_bot_protection_page');
        }
        console.log('[sold-listings-decodo] async task received', {
          taskId: data.task_id,
          status: data?.status ?? null,
          statusCode: data?.status_code ?? null,
          query,
        });
        html = await fetchDecodoTaskResultHtml(data.task_id, authValue, timeoutMs);
      }
      if (!html) {
        console.warn('[sold-listings-decodo] empty html payload', {
          hasResults: Array.isArray(data?.results),
          topLevelKeys: Object.keys(data ?? {}).slice(0, 12),
          query,
        });
        return [];
      }
      if (isEbaySecurityPage(html)) throw new Error('ebay_bot_protection_page');
      const rows = parseSoldListingsFromHtml(html, maxItems);
      if (rows.length === 0) {
        const htmlSnippet = html
          .replace(/\s+/g, ' ')
          .slice(0, 300)
          .toLowerCase();
        console.warn('[sold-listings-decodo] parsed 0 rows', {
          query,
          htmlSnippet,
          hasEbayMarkers: html.toLowerCase().includes('ebay'),
          hasSrpResults: html.toLowerCase().includes('srp-results'),
          hasSItem: html.toLowerCase().includes('s-item'),
        });
      }
      return normalizeProviderItems(rows)
        .filter((item: any) => !item.itemEndDate || new Date(item.itemEndDate) >= cutoff);
    }
    return [];
  } catch (error: any) {
    if (error?.name === 'AbortError') throw new Error('decodo_timeout');
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
