/**
 * CardSight HTTP fetch with retry on rate limits and transient errors.
 */

export class CardsightApiError extends Error {
  readonly status: number;

  constructor(status: number, message?: string) {
    super(message ?? `CardSight API error: ${status}`);
    this.name = 'CardsightApiError';
    this.status = status;
  }

  get isRateLimited(): boolean {
    return this.status === 429;
  }
}

function retryDelayMs(res: Response, attempt: number, baseDelayMs: number): number {
  const retryAfter = res.headers.get('Retry-After');
  if (retryAfter) {
    const seconds = Number.parseInt(retryAfter, 10);
    if (Number.isFinite(seconds) && seconds > 0) return seconds * 1000;
    const until = Date.parse(retryAfter);
    if (!Number.isNaN(until)) return Math.max(0, until - Date.now());
  }
  return baseDelayMs * Math.pow(2, attempt);
}

export type CardsightFetchOptions = RequestInit & {
  maxRetries?: number;
  baseDelayMs?: number;
};

/** Fetch with `X-API-Key`; retries 429 / 502 / 503 with exponential backoff. */
export async function cardsightFetch(
  url: string | URL,
  apiKey: string,
  options: CardsightFetchOptions = {},
): Promise<Response> {
  const { maxRetries = 4, baseDelayMs = 1500, ...fetchInit } = options;
  const headers = new Headers(fetchInit.headers);
  headers.set('X-API-Key', apiKey);

  let lastStatus = 0;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const res = await fetch(url.toString(), { ...fetchInit, headers });
    if (res.ok) return res;

    lastStatus = res.status;
    const retryable = res.status === 429 || res.status === 502 || res.status === 503;
    if (!retryable || attempt >= maxRetries) break;

    const delay = retryDelayMs(res, attempt, baseDelayMs);
    console.warn(
      `[cardsight] HTTP ${res.status} — retry ${attempt + 1}/${maxRetries} in ${delay}ms`,
      url.toString(),
    );
    await new Promise((r) => setTimeout(r, delay));
  }

  throw new CardsightApiError(lastStatus);
}

/** Map CardSight errors to edge HTTP status (429 → 429, else 500). */
export function cardsightErrorResponse(
  e: unknown,
  cors: Record<string, string>,
  rateLimitMessage = 'CardSight rate limit — monthly quota may be exhausted',
): Response {
  const headers = { ...cors, 'Content-Type': 'application/json' };
  if (e instanceof CardsightApiError && e.isRateLimited) {
    return new Response(
      JSON.stringify({ error: rateLimitMessage, code: 'RATE_LIMITED' }),
      { status: 429, headers },
    );
  }
  const msg = e instanceof Error ? e.message : String(e);
  return new Response(JSON.stringify({ error: msg }), { status: 500, headers });
}
