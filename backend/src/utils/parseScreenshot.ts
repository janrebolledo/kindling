import { getAIOutputText, type AIClient, type AIRequest } from '../clients';
import { parseScreenshotPrompt } from '../prompts';
import type { Screenshot } from '../types';

const MODEL = 'gpt-5.6-luna';

const screenshotExtractionSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    results: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          data: {
            type: 'object',
            additionalProperties: false,
            properties: {
              status: { type: 'string', enum: ['success', 'skipped', 'sensitive'] },
              reason: { type: ['string', 'null'] },
              item: {
                type: ['object', 'null'],
                additionalProperties: false,
                properties: {
                  name: { type: ['string', 'null'] },
                  venue: { type: ['string', 'null'] },
                  location: { type: ['string', 'null'] },
                  address: { type: ['string', 'null'] },
                  date: { type: ['string', 'null'] },
                  time: { type: ['string', 'null'] },
                  distance_miles: { type: ['number', 'null'] },
                  completion_time: { type: ['string', 'null'] },
                  tag: { type: 'string', enum: ['activity', 'event', 'food'] },
                  activity_type: { type: ['string', 'null'] },
                  activity_emoji: { type: ['string', 'null'] },
                  description: { type: ['string', 'null'] },
                  highlights: { type: ['string', 'null'] },
                  highlights_sources: {
                    type: ['array', 'null'],
                    items: { type: 'string' },
                  },
                },
                required: [
                  'name', 'venue', 'location', 'address', 'date', 'time',
                  'distance_miles', 'completion_time', 'tag', 'activity_type',
                  'activity_emoji', 'description', 'highlights', 'highlights_sources',
                ],
              },
            },
            required: ['status', 'reason', 'item'],
          },
        },
        required: ['id', 'data'],
      },
    },
  },
  required: ['results'],
} satisfies Record<string, unknown>;

async function generateWithRetry(
  ai: AIClient,
  params: AIRequest,
  maxRetries = 5,
) {
  let delay = 1000;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await ai.responses.create(params);
    } catch (err: unknown) {
      const status =
        err && typeof err === 'object'
          ? ((err as { status?: number }).status ??
            (err as { httpError?: { status?: number } }).httpError?.status ??
            (err as { response?: { status?: number } }).response?.status)
          : undefined;
      if ((status === 429 || (status != null && status >= 500)) && attempt < maxRetries) {
        await new Promise((res) => setTimeout(res, delay));
        delay *= 2;
        continue;
      }
      throw err;
    }
  }
  throw new Error('Unreachable');
}

export async function parseScreenshot(
  screenshots: Screenshot[],
  ai: AIClient,
) {
  const response = await generateWithRetry(ai, {
    model: MODEL,
    instructions: parseScreenshotPrompt,
    input: JSON.stringify(screenshots),
    reasoning: { effort: 'none' },
    text: {
      format: {
        type: 'json_schema',
        name: 'screenshot_extractions',
        strict: true,
        schema: screenshotExtractionSchema,
      },
    },
  });

  const parsed = JSON.parse(getAIOutputText(response) || '{"results":[]}') as {
    results?: ExtractionResult[];
  };
  return parsed.results ?? [];
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
  distance_miles: number | null;
  completion_time: string | null;
  tag: ExtractionTag;
  activity_type: string | null;
  activity_emoji: string | null;
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
