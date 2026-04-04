import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Derive the Supabase project URL from the postgres connection string
// e.g. postgresql://postgres:pass@db.PROJECTREF.supabase.co:5432/postgres
function createSupabaseClient(): SupabaseClient {
  const dbUrl = new URL(process.env.DATABASE_URL!);
  const projectRef = dbUrl.hostname.replace(/^db\./, '').replace(/\.supabase\.co$/, '');
  const supabaseUrl = `https://${projectRef}.supabase.co`;
  return createClient(supabaseUrl, process.env.SUPABASE_SERVICE_ROLE_KEY!);
}

export const supabase = createSupabaseClient();
