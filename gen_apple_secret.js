const jwt = require('jsonwebtoken');
const fs = require('fs');

// ── Fill these in ──────────────────────────────────────────────
const TEAM_ID    = '9GJ85MHPT8';          // 10-char, top-right on developer.apple.com
const KEY_ID     = 'K79X7BQ923';           // 10-char, from the Key detail page
const CLIENT_ID  = 'com.mlabs.cardvault'; // your Services ID
const P8_FILE    = '/Users/apple/Documents/Repos/CardVault/mobile/AuthKey_K79X7BQ923.p8'; // path to the downloaded .p8 file
// ──────────────────────────────────────────────────────────────

const privateKey = fs.readFileSync(P8_FILE, 'utf8');

const token = jwt.sign(
  {
    iss: TEAM_ID,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 86400 * 180, // 6 months
    aud: 'https://appleid.apple.com',
    sub: CLIENT_ID,
  },
  privateKey,
  { algorithm: 'ES256', keyid: KEY_ID }
);

console.log('\n── Paste this into Supabase → Apple → Secret Key ──\n');
console.log(token);
console.log('\n── Expires in 6 months — regenerate before then ──\n');
