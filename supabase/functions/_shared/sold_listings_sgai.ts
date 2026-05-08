/**
 * Sold listings via ScrapeGraphAI scraping eBay completed search HTML.
 */

const SCRAPEGRAPH_SCRAPE_URL = 'https://v2-api.scrapegraphai.com/api/scrape';
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

function isEbaySecurityPage(html: string): boolean {
  const t = html.toLowerCase();
  return t.includes('<title>security measure') ||
    t.includes('captcha') ||
    t.includes('robot check') ||
    t.includes('verify you are human');
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
