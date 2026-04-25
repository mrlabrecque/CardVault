import { createClient } from 'jsr:@supabase/supabase-js@2';

const SCRAPECHAIN_URL = 'https://ebay-api.scrapechain.com/findCompletedItems';
const DELAY_MS = 300;
const BATCH_SIZE = 20;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Calculate Monday of the current ISO week for snapshot dedup
function getISOWeekMonday(): string {
  const now = new Date();
  const day = now.getDay();
  const diff = now.getDate() - day + (day === 0 ? -6 : 1); // adjust when day is Sunday
  const monday = new Date(now.setDate(diff));
  return monday.toISOString().split('T')[0]; // YYYY-MM-DD
}

// Fetch athlete details in large parallel batches to get names
async function fetchAthleteDetails(
  baseUrl: string,
  espnIds: string[],
): Promise<Map<string, string>> {
  const athletes = new Map<string, string>(); // espnId -> name
  const batchSize = 20; // Parallel batches
  const maxAthletes = 40; // Top 40 per sport (160 total—what you need for display)

  if (espnIds.length === 0) {
    console.log(`[market-movers] No athlete IDs to fetch`);
    return athletes;
  }

  const limitedIds = espnIds.slice(0, maxAthletes);
  console.log(`[market-movers] Fetching details for ${limitedIds.length}/${espnIds.length} athletes in batches of ${batchSize}`);

  for (let i = 0; i < limitedIds.length; i += batchSize) {
    const batch = limitedIds.slice(i, i + batchSize);
    console.log(`[market-movers] Batch ${Math.floor(i/batchSize) + 1}: fetching ${batch.length} athletes`);

    const promises = batch.map(async (espnId) => {
      try {
        const athleteUrl = `${baseUrl}/athletes/${espnId}`;
        const res = await fetch(athleteUrl);
        if (res.ok) {
          const data = await res.json();
          const name = data.displayName ?? data.fullName ?? '';
          if (name) {
            console.log(`[market-movers]   ✓ ${espnId}: ${name}`);
            return { espnId, name };
          }
        } else {
          console.warn(`[market-movers]   ✗ ${espnId}: HTTP ${res.status}`);
        }
      } catch (e: any) {
        console.error(`[market-movers]   ✗ ${espnId}: ${e.message}`);
      }
      return null;
    });

    const results = await Promise.all(promises);
    for (const result of results) {
      if (result) athletes.set(result.espnId, result.name);
    }

  }

  console.log(`[market-movers] Successfully fetched ${athletes.size} athlete names`);
  return athletes;
}

// Fetch ESPN leaders for a sport
async function fetchESPNLeaders(
  sport: { key: string; league: string; label: string },
  year: number,
  admin: any,
): Promise<Array<{ name: string; espnId: string }>> {
  const seasonUrl = `https://sports.core.api.espn.com/v2/sports/${sport.key}/leagues/${sport.league}/seasons/${year}`;
  const url = `${seasonUrl}/types/2/leaders`;

  try {
    console.log(`[market-movers] Fetching ${sport.label} from ${url}`);
    const res = await fetch(url);

    if (!res.ok) {
      const body = await res.text();
      console.error(`[market-movers] ESPN ${sport.label} failed: ${res.status} - ${body}`);
      return [];
    }

    const data = await res.json();
    const categories = data.categories ?? [];
    console.log(`[market-movers] ${sport.label} got ${categories.length} categories`);

    // Collect all athlete espn IDs from all categories
    const espnIds = new Set<string>();
    for (const cat of categories) {
      const leaders = cat.leaders ?? [];
      console.log(`[market-movers] ${sport.label} category "${cat.name}": ${leaders.length} leaders`);
      for (const leader of leaders) {
        const athleteRef = leader.athlete?.$ref ?? '';
        if (athleteRef) {
          // Extract ESPN ID from URL like ".../athletes/123456"
          const match = athleteRef.match(/\/athletes\/(\d+)\?/);
          if (match) {
            espnIds.add(match[1]);
          }
        }
      }
    }

    console.log(`[market-movers] ${sport.label}: extracted ${espnIds.size} unique athlete IDs`);

    // Check which athletes already have names cached in the DB
    const { data: existingPlayers } = await admin
      .from('top_players')
      .select('espn_id, name')
      .in('espn_id', Array.from(espnIds));

    const cachedNames = new Map<string, string>();
    const missingIds = new Set<string>();

    for (const player of existingPlayers ?? []) {
      if (player.name) {
        cachedNames.set(player.espn_id, player.name);
      } else {
        missingIds.add(player.espn_id);
      }
    }

    // Fetch only names for new/missing athletes
    for (const id of espnIds) {
      if (!cachedNames.has(id)) {
        missingIds.add(id);
      }
    }

    console.log(`[market-movers] ${sport.label}: ${cachedNames.size} cached, ${missingIds.size} to fetch`);
    const newNames = await fetchAthleteDetails(seasonUrl, Array.from(missingIds));

    // Combine cached + newly fetched names
    const athleteNames = new Map([...cachedNames, ...newNames]);
    console.log(`[market-movers] ${sport.label}: fetched names for ${athleteNames.size} athletes`);

    // Convert to result array (top 100)
    const result = Array.from(athleteNames.entries())
      .slice(0, 100)
      .map(([espnId, name]) => ({ name, espnId }));

    console.log(`[market-movers] ${sport.label}: returning ${result.length} players`);
    return result;
  } catch (e: any) {
    console.error(`[market-movers] ESPN ${sport.label} error: ${e.message}`);
    return [];
  }
}

// Fetch sold listings from Scrapechain
async function fetchSoldListings(query: string): Promise<{ avgPrice: number; compCount: number } | null> {
  try {
    const res = await fetch(SCRAPECHAIN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        keywords: query,
        max_search_results: 120,
        remove_outliers: false,
        category_id: '261328', // Sports Trading Cards
      }),
    });

    if (!res.ok) {
      console.warn(`[market-movers] Scrapechain ${query}: ${res.status}`);
      return null;
    }

    const data = await res.json();
    const products = data.products ?? [];

    if (products.length === 0) {
      return null;
    }

    const avgPrice = data.average_price ?? 0;
    const compCount = products.length;

    return { avgPrice, compCount };
  } catch (e: any) {
    console.error(`[market-movers] Scrapechain ${query} error: ${e.message}`);
    return null;
  }
}

// Main handler
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: CORS_HEADERS });
  }

  // Auth: service role key (for cron) or valid JWT (for dashboard testing)
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Allow either service role key (from cron) or any valid JWT (from dashboard/users)
  const isServiceRole = token === serviceRoleKey;
  const hasValidJWT = token.length > 0; // Dashboard sends a JWT, just check it exists

  if (!isServiceRole && !hasValidJWT) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: CORS_HEADERS,
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const startTime = Date.now();
  const year = new Date().getFullYear();
  const snapshotWeek = getISOWeekMonday();

  const sports = [
    { key: 'football', league: 'nfl', label: 'NFL' },
    { key: 'basketball', league: 'nba', label: 'NBA' },
    { key: 'baseball', league: 'mlb', label: 'MLB' },
    { key: 'hockey', league: 'nhl', label: 'NHL' },
  ];

  // ── Step 1: Sync top players from ESPN ──────────────────────────────────────

  const allPlayers: Array<{ name: string; espnId: string; sport: string }> = [];
  const seenEspnIds = new Set<string>();

  for (const sport of sports) {
    const players = await fetchESPNLeaders(sport, year, admin);
    console.log(`[market-movers] Synced ${players.length} players from ${sport.label}`);

    // Deduplicate by ESPN ID (some players might appear across multiple sports)
    for (const p of players) {
      if (!seenEspnIds.has(p.espnId)) {
        seenEspnIds.add(p.espnId);
        allPlayers.push({ ...p, sport: sport.label });
      }
    }
  }

  console.log(`[market-movers] Total unique players from all sports: ${allPlayers.length}`);

  if (allPlayers.length === 0) {
    console.warn('[market-movers] No players from ESPN, trying alternate approach...');
    // Fallback: fetch a few popular players manually for testing
    allPlayers.push(
      { name: 'Patrick Mahomes', espnId: '33991669', sport: 'NFL' },
      { name: 'LeBron James', espnId: '2325315', sport: 'NBA' },
      { name: 'Shohei Ohtani', espnId: '33966', sport: 'MLB' },
      { name: 'Connor McDavid', espnId: '3050465', sport: 'NHL' },
    );
    console.log(`[market-movers] Using fallback players: ${allPlayers.length}`);
  }

  // Upsert to top_players (try insert first, then update on conflict)
  const playersToUpsert = allPlayers.map(p => ({
    name: p.name,
    sport: p.sport,
    espn_id: p.espnId,
    last_synced_at: new Date().toISOString(),
  }));

  // Deduplicate by ESPN ID
  const uniquePlayers = new Map<string, any>();
  for (const p of playersToUpsert) {
    uniquePlayers.set(p.espn_id, p);
  }

  const playersArray = Array.from(uniquePlayers.values());

  // Try insert, ignore duplicates (preserves cached names)
  const { error: insertError } = await admin
    .from('top_players')
    .insert(playersArray);

  // Duplicates are OK—we're just adding new athletes
  if (insertError && !insertError.message.includes('duplicate')) {
    console.error(`[market-movers] Failed to insert top_players: ${insertError.message}`);
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }

  // Update timestamps for existing players (they already have names cached)
  for (const espnId of uniquePlayers.keys()) {
    await admin
      .from('top_players')
      .update({ last_synced_at: new Date().toISOString() })
      .eq('espn_id', espnId);
  }

  // ── Step 2: Fetch and snapshot Scrapechain data ────────────────────────────

  // Fetch all players with their IDs
  const { data: topPlayersData, error: fetchError } = await admin
    .from('top_players')
    .select('id, name, sport')
    .order('sport, name');

  if (fetchError) {
    console.error(`[market-movers] Failed to fetch top_players: ${fetchError.message}`);
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }

  const players = topPlayersData ?? [];
  console.log(`[market-movers] Fetched ${players.length} top players for Scrapechain queries`);

  let snapshotsWritten = 0;
  let failed = 0;

  // Process in batches
  for (let i = 0; i < players.length; i += BATCH_SIZE) {
    const batch = players.slice(i, i + BATCH_SIZE);

    for (const player of batch) {
      const query = player.name; // e.g. "Caitlin Clark"

      const result = await fetchSoldListings(query);

      if (result && result.compCount > 0) {
        const { error: insertError } = await admin.from('market_movers_snapshots').insert({
          top_player_id: player.id,
          avg_price: result.avgPrice,
          comp_count: result.compCount,
          snapshot_week: snapshotWeek,
          query: query,
        });

        // Duplicate snapshots are OK (same player, same week)
        if (insertError && !insertError.message.includes('duplicate')) {
          console.error(`[market-movers] Failed to snapshot ${player.name}: ${insertError.message}`);
          failed++;
        } else {
          console.log(
            `[market-movers] ✓ ${player.name} — $${result.avgPrice.toFixed(2)} (${result.compCount} comps)`,
          );
          snapshotsWritten++;
        }
      } else {
        console.log(`[market-movers] ⊘ ${player.name} — no comps found`);
      }

      // Delay between requests
      if (players.indexOf(player) < players.length - 1) {
        await new Promise(r => setTimeout(r, DELAY_MS));
      }
    }

    // Extra delay between batches
    if (i + BATCH_SIZE < players.length) {
      await new Promise(r => setTimeout(r, 500));
    }
  }

  const duration = Date.now() - startTime;
  console.log(
    `[market-movers] Complete: ${snapshotsWritten} snapshots, ${failed} failed, ${duration}ms`,
  );

  return new Response(
    JSON.stringify({
      playersSynced: allPlayers.length,
      snapshotsWritten,
      failed,
      duration,
    }),
    { headers: { 'Content-Type': 'application/json', ...CORS_HEADERS } },
  );
});
