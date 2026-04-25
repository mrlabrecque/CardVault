import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const CARDSIGHT_API_KEY = Deno.env.get("CARDSIGHT_API_KEY")!
const CARDSIGHT_BASE = "https://api.cardsight.ai/v1"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const { cardsightReleaseId, name = "", take = 20 } = await req.json()

    if (!cardsightReleaseId) {
      return new Response(JSON.stringify({ error: "cardsightReleaseId required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    // Build query params
    const params = new URLSearchParams({ take: String(take) })
    if (name) params.set("name", name)

    // Call CardSight API
    const csRes = await fetch(
      `${CARDSIGHT_BASE}/catalog/releases/${cardsightReleaseId}/cards?${params}`,
      { headers: { "X-Api-Key": CARDSIGHT_API_KEY } }
    )

    if (!csRes.ok) {
      return new Response(JSON.stringify({ error: "CardSight API error" }), {
        status: csRes.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const data = await csRes.json()

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
