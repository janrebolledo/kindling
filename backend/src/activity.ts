import { GoogleGenAI, Type } from '@google/genai';
import type { ExtractedItem } from './utils/parseScreenshot';
import { log, logError } from './log';

const MODEL = 'gemini-3.5-flash-lite';

export type ActivityDetails = {
  distance_miles: number | null;
  completion_time: string | null;
};

const activityDetailsSchema = {
  type: Type.OBJECT,
  properties: {
    distance_miles: {
      type: Type.NUMBER,
      nullable: true,
      description: 'The listed route distance in miles. Use null when it is not reliably available.',
    },
    completion_time: {
      type: Type.STRING,
      nullable: true,
      description: 'The typical time to complete the route, preserving a range when sources provide one. Use null when it is not reliably available.',
    },
  },
  required: ['distance_miles', 'completion_time'],
};

function searchableActivityText(item: ExtractedItem): string {
  return [
    item.venue,
    item.location,
    item.address,
    item.activity_type,
    item.description,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}

/** Restrict web lookups to activities where route distance/time are useful. */
export function isDistanceBasedActivity(item: ExtractedItem): boolean {
  if (item.tag !== 'activity') return false;
  return /\b(hike|hiking|trail|trek|walk|waterfall|canyon|peak|summit|loop|outdoor|bike|biking|cycling|climb|mountain|preserve|reserve)\b/i.test(
    searchableActivityText(item),
  );
}

function normalizeDetails(value: unknown): ActivityDetails | null {
  if (value == null || typeof value !== 'object') return null;
  const candidate = value as {
    distance_miles?: unknown;
    completion_time?: unknown;
  };

  const distance = typeof candidate.distance_miles === 'number'
    && Number.isFinite(candidate.distance_miles)
    && candidate.distance_miles >= 0
    && candidate.distance_miles <= 1000
    ? Math.round(candidate.distance_miles * 10) / 10
    : null;
  const completion = typeof candidate.completion_time === 'string'
    ? candidate.completion_time.trim().slice(0, 120) || null
    : null;

  return distance == null && completion == null
    ? null
    : { distance_miles: distance, completion_time: completion };
}

function parseJSON(text: string): unknown {
  const trimmed = text.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const object = trimmed.match(/\{[\s\S]*\}/)?.[0];
    return object ? JSON.parse(object) : null;
  }
}

/**
 * Uses Gemini's Google Search grounding to find trail facts. This is
 * deliberately best-effort: the idea itself should still save if a trail has
 * ambiguous naming, no public listing, or the search service is unavailable.
 */
export async function lookupActivityDetails(
  ai: GoogleGenAI,
  item: ExtractedItem,
): Promise<ActivityDetails | null> {
  if (!isDistanceBasedActivity(item) || !item.venue) return null;

  const query = [item.venue, item.location, item.address]
    .filter(Boolean)
    .join(', ');

  try {
    log('gemini_activity.search_request', {
      venue: item.venue,
      query_length: query.length,
    });

    const response = await ai.models.generateContent({
      model: MODEL,
      contents: `Search the web for the official or most authoritative listing for this hiking or outdoor route: ${query}

Return the route distance in miles and the typical time to complete the route. Prefer the named trail or route over a similarly named business. Do not infer or combine values from unrelated trails. If sources disagree or the route cannot be identified confidently, return null for that field. Return only JSON matching the requested schema.`,
      config: {
        tools: [{ googleSearch: {} }],
        responseMimeType: 'application/json',
        responseSchema: activityDetailsSchema,
      },
    });

    const details = normalizeDetails(parseJSON(response.text ?? ''));
    log('gemini_activity.search_response', {
      venue: item.venue,
      found_distance: details?.distance_miles != null,
      found_completion_time: details?.completion_time != null,
    });
    return details;
  } catch (err) {
    logError('gemini_activity.search_failed', err, { venue: item.venue });
    return null;
  }
}
