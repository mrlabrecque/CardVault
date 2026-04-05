import { createClient, SupabaseClient } from '@supabase/supabase-js';

function createSupabaseClient(): SupabaseClient {
  const supabaseUrl = process.env.SUPABASE_URL!;
  const apiKey = process.env.SUPABASE_ANON_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY!;
  return createClient(supabaseUrl, apiKey);
}

export const supabase = createSupabaseClient();
