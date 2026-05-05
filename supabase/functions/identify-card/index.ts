Deno.serve(async (req) => {
  console.log('[identify-card] received request');

  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  try {
    const body = await req.json();
    const imageBase64 = body?.imageBase64;
    const sport = body?.sport || 'baseball';

    console.log('[identify-card] sport:', sport, 'image size:', imageBase64?.length);

    if (!imageBase64) {
      return new Response(
        JSON.stringify({ error: 'imageBase64 is required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const apiKey = Deno.env.get('CARDSIGHT_API_KEY');
    if (!apiKey) {
      console.error('[identify-card] CARDSIGHT_API_KEY not set');
      return new Response(
        JSON.stringify({ error: 'API key not configured' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    // Decode base64 to binary
    const binaryString = atob(imageBase64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }

    // Create FormData with the image blob
    const formData = new FormData();
    const blob = new Blob([bytes], { type: 'image/jpeg' });
    formData.append('file', blob, 'card.jpg');

    const url = `https://api.cardsight.ai/v1/identify/card/${sport}`;
    console.log('[identify-card] calling:', url);

    const controller = new AbortController();
    const timeoutMs = 60000;
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          'X-Api-Key': apiKey,
        },
        body: formData,
        signal: controller.signal,
      });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') {
        console.error('[identify-card] CardSight timeout after', timeoutMs, 'ms');
        return new Response(
          JSON.stringify({ error: 'CardSight request timed out' }),
          { status: 504, headers: { 'Content-Type': 'application/json' } }
        );
      }
      throw err;
    } finally {
      clearTimeout(timeout);
    }

    console.log('[identify-card] CardSight response:', response.status);

    if (!response.ok) {
      const errorText = await response.text();
      console.error('[identify-card] CardSight error:', errorText);
      return new Response(
        JSON.stringify({ error: `CardSight error: ${response.status}`, details: errorText }),
        { status: response.status, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const result = await response.json();
    console.log('[identify-card] success, detections:', result.detections?.length || 0);

    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('[identify-card] exception:', e);
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});
