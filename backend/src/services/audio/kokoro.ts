const KOKORO_SERVICE_URL = process.env.KOKORO_TTS_URL || 'https://kokoro-tts-801121217326.us-east1.run.app';

interface KokoroSegmentResult {
  segment_id: string;
  audio_url: string;
  duration_seconds: number;
  file_size_bytes: number;
  content_hash: string;
}

interface KokoroBatchResponse {
  segments: KokoroSegmentResult[];
  total_duration_seconds: number;
  total_size_bytes: number;
}

export async function synthesizeWithKokoro(
  segments: Array<{ id: string; narration_text: string; content_hash: string; language: string }>,
  voice: string = 'af_heart',
  speed: number = 0.95,
): Promise<KokoroBatchResponse> {
  const response = await fetch(`${KOKORO_SERVICE_URL}/batch`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ segments, voice, speed }),
    signal: AbortSignal.timeout(300_000),  // 5 min for large tours
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Kokoro TTS failed (${response.status}): ${text}`);
  }

  return response.json() as Promise<KokoroBatchResponse>;
}

export async function isKokoroAvailable(): Promise<boolean> {
  try {
    const response = await fetch(`${KOKORO_SERVICE_URL}/health`, {
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
