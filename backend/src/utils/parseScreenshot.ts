import { ai } from '../clients';
import { parseScreenshotPrompt } from '../prompts';
import type { Screenshot } from '../types';

const MODEL = 'gemini-3.5-flash-lite';

async function generateWithRetry(
  params: Parameters<typeof ai.models.generateContent>[0],
  maxRetries = 5,
) {
  let delay = 1000;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await ai.models.generateContent(params);
    } catch (err: unknown) {
      const status =
        err && typeof err === 'object'
          ? ((err as { status?: number }).status ??
            (err as { httpError?: { status?: number } }).httpError?.status ??
            (err as { response?: { status?: number } }).response?.status)
          : undefined;
      if (status === 503 && attempt < maxRetries) {
        await new Promise((res) => setTimeout(res, delay));
        delay *= 2;
        continue;
      }
      throw err;
    }
  }
  throw new Error('Unreachable');
}

export async function parseScreenshot(screenshots: Screenshot[]) {
  const response = await generateWithRetry({
    model: MODEL,
    contents: parseScreenshotPrompt + JSON.stringify(screenshots),
  });

  return JSON.parse(response.text || '[]') as ExtractionResult[];
}

type ExtractionStatus = 'success' | 'skipped' | 'sensitive';

type ExtractionTag = 'activity' | 'event' | 'food';

export type ExtractedItem = {
  name: string | null;
  venue: string | null;
  location: string | null;
  address: string | null;
  date: string | null;
  time: string | null;
  tag: ExtractionTag;
  activity_type: string | null;
  description: string | null;
  highlights: string | null;
  highlights_sources: string[] | null;
};

export type ExtractionResult = {
  id: string;
  data: {
    status: ExtractionStatus;
    reason: string | null;
    item: ExtractedItem | null;
  };
};
