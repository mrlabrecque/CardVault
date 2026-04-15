import { WishlistSeed } from '../../features/wishlist/add-to-wishlist-dialog/add-to-wishlist-dialog';

// Known grading companies
const GRADERS = ['PSA', 'BGS', 'BVG', 'SGC', 'CGC', 'CSG', 'HGA'];

// Common card brand / manufacturer tokens — helps us avoid treating these as player names
const BRAND_TOKENS = [
  'Panini', 'Topps', 'Upper', 'Deck', 'Bowman', 'Leaf', 'Donruss',
  'Select', 'Mosaic', 'Optic', 'Fleer', 'Score', 'Stadium', 'Club',
  'National', 'Treasures', 'Immaculate', 'Certified', 'Absolute',
  'Prizm', 'Chrome', 'Heritage', 'Archives', 'Finest', 'Elements',
  'Inception', 'Canvas', 'Series', 'Draft', 'Prospects',
];

// Common parallel name fragments
const PARALLEL_TOKENS = [
  'Silver', 'Gold', 'Blue', 'Red', 'Orange', 'Green', 'Purple', 'Pink',
  'Black', 'White', 'Teal', 'Aqua', 'Bronze', 'Copper', 'Holo', 'Hyper',
  'Refractor', 'Prizm', 'Wave', 'Disco', 'Neon', 'Pulsar', 'Mosaic',
  'Cracked', 'Ice', 'Scope', 'Choice', 'Shimmer', 'Mojo', 'Kaboom',
  'Fireworks', 'Wedge', 'Choice', 'Vector', 'Stained', 'Glass',
  'Young', 'Guns', 'Canvas', 'Clear', 'Cut',
];

/**
 * Parse a raw eBay listing title + the user's search query into a WishlistSeed.
 * The search query is the most reliable source for the player name since the
 * user typed it. The title fills in set/parallel/grade/attributes.
 */
export function parseEbayTitle(title: string, searchQuery: string, soldPrice: number | null): WishlistSeed {
  const seed: WishlistSeed = { suggested_price: soldPrice };

  // ── Year ─────────────────────────────────────────────────────────────────
  const yearMatch = title.match(/\b(19|20)\d{2}(?:-\d{2})?\b/);
  if (yearMatch) {
    // Handle "2023-24" style — take the first year
    seed.year = parseInt(yearMatch[0].split('-')[0], 10);
  }

  // ── Grade ─────────────────────────────────────────────────────────────────
  const graderPattern = new RegExp(`\\b(${GRADERS.join('|')})\\s*(\\d+(?:\\.\\d+)?)\\b`, 'i');
  const gradeMatch = title.match(graderPattern);
  if (gradeMatch) {
    seed.grade = `${gradeMatch[1].toUpperCase()} ${gradeMatch[2]}`;
  }

  // ── Serial max (/99, /25, etc.) ───────────────────────────────────────────
  const serialMatch = title.match(/\/(\d{1,4})\b/);
  if (serialMatch) {
    seed.serial_max = parseInt(serialMatch[1], 10);
  }

  // ── Attributes ────────────────────────────────────────────────────────────
  seed.is_rookie = /\bRC\b|\brookie\b/i.test(title);
  seed.is_auto   = /\bauto(?:graph)?\b/i.test(title);
  seed.is_patch  = /\bpatch\b|\bmemo(?:rabilia)?\b/i.test(title);

  // ── Player name — derive from search query ────────────────────────────────
  // Strip year, grader/grade, /serial, and known brand tokens from the query
  // to isolate what's most likely the player name.
  let playerRaw = searchQuery
    .replace(/\b(19|20)\d{2}(?:-\d{2})?\b/g, '')         // years
    .replace(graderPattern, '')                            // grade
    .replace(/\/\d{1,4}\b/g, '')                          // /serial
    .replace(/\bRC\b|\brookie\b/gi, '')                    // RC
    .replace(/\bauto(?:graph)?\b/gi, '')                   // auto
    .replace(/\bpatch\b/gi, '')                            // patch
    .replace(/\bPSA|BGS|SGC|CGC|CSG\b/gi, '')             // stray grader names
    .trim()
    .replace(/\s{2,}/g, ' ');

  // Remove trailing brand/set tokens that leaked in (e.g. "Bedard Prizm")
  const brandRe = new RegExp(`\\b(${[...BRAND_TOKENS, ...PARALLEL_TOKENS].join('|')})\\b`, 'gi');
  const playerCleaned = playerRaw.replace(brandRe, '').trim().replace(/\s{2,}/g, ' ');

  // Use the cleaned version if it left something meaningful, otherwise keep the raw query
  seed.player = playerCleaned.length >= 3 ? playerCleaned : playerRaw;

  // ── Parallel — look for known parallel tokens in the title ────────────────
  // Build a regex from known parallel tokens
  const parallelRe = new RegExp(`\\b(${PARALLEL_TOKENS.join('|')})\\b`, 'gi');
  const parallelMatches = [...title.matchAll(parallelRe)].map(m => m[0]);

  // Deduplicate while preserving order
  const seen = new Set<string>();
  const parallelParts: string[] = [];
  for (const p of parallelMatches) {
    const key = p.toLowerCase();
    if (!seen.has(key)) { seen.add(key); parallelParts.push(p); }
  }
  if (parallelParts.length > 0) {
    seed.parallel = parallelParts.join(' ');
  }

  // ── Set name — strip player, year, grade, serial, attrs, parallel from title ──
  let setRaw = title
    .replace(yearMatch?.[0] ?? '__NOOP__', '')
    .replace(gradeMatch?.[0] ?? '__NOOP__', '')
    .replace(/\/\d{1,4}\b/g, '')
    .replace(/\bRC\b|\brookie\b/gi, '')
    .replace(/\bauto(?:graph)?\b/gi, '')
    .replace(/\bpatch\b|\bmemo(?:rabilia)?\b/gi, '')
    .replace(new RegExp(`\\b${escapeRe(seed.player ?? '')}\\b`, 'gi'), '')
    .replace(parallelRe, '')         // remove parallel tokens we already captured
    .replace(/\s{2,}/g, ' ')
    .trim();

  // What's left should be mostly brand + product name tokens
  // Keep tokens that are brand-like or capitalized words (set names are usually title-case)
  const setTokens = setRaw.split(/\s+/).filter(t =>
    t.length > 1 &&
    !/^\d+$/.test(t) &&
    /^[A-Z]/.test(t)
  );
  if (setTokens.length > 0) {
    seed.set_name = setTokens.join(' ');
  }

  return seed;
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
