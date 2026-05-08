/**
 * Validates Supabase user JWT from Authorization Bearer header (ES256 JWKS).
 */

function b64urlToBytes(b64url: string): Uint8Array {
  const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}

function b64urlToJson(b64url: string): any {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(b64url)));
}

let cachedJwks: any[] | null = null;

async function getJwks(supabaseUrl: string): Promise<any[]> {
  if (cachedJwks) return cachedJwks;
  const res = await fetch(`${supabaseUrl}/auth/v1/.well-known/jwks.json`);
  const data = await res.json();
  cachedJwks = data.keys ?? [];
  return cachedJwks!;
}

export async function verifyUserJwt(
  bearerTokenFull: string,
  supabaseUrl: string,
): Promise<string | null> {
  const token = bearerTokenFull.replace(/^Bearer\s+/i, '');
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const header = b64urlToJson(parts[0]);
    const payload = b64urlToJson(parts[1]);
    const jwks = await getJwks(supabaseUrl);
    const jwk = jwks.find((k: any) => k.kid === header.kid) ?? jwks[0];
    if (!jwk) return null;
    const key = await crypto.subtle.importKey(
      'jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify'],
    );
    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' }, key,
      b64urlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
    if (!valid) return null;
    return payload?.sub ?? null;
  } catch {
    return null;
  }
}
