import { GoogleGenAI, Type } from '@google/genai';
import type { ExtractedItem } from './utils/parseScreenshot';
import { log, logError } from './log';

const MODEL = 'gemini-3.5-flash-lite';

export type ActivityDetails = {
  distance_miles: number | null;
  completion_time: string | null;
};

function normalizeDistance(value: unknown): number | null {
  if (typeof value === 'number') {
    return Number.isFinite(value) && value >= 0 && value <= 1000
      ? Math.round(value * 10) / 10
      : null;
  }
  if (typeof value !== 'string') return null;

  const match = value.replace(/,/g, '').match(/(\d+(?:\.\d+)?)\s*(mi|miles?|km|kilometers?|ft|feet)?/i);
  if (!match) return null;
  const rawDistance = Number.parseFloat(match[1]);
  const unit = match[2]?.toLowerCase();
  const distance = unit?.startsWith('ft') || unit === 'feet'
    ? rawDistance / 5280
    : unit === 'km' || unit?.startsWith('kilometer')
      ? rawDistance * 0.621371
      : rawDistance;

  return Number.isFinite(distance) && distance >= 0 && distance <= 1000
    ? Math.round(distance * 10) / 10
    : null;
}

function normalizeCompletionTime(value: unknown): string | null {
  return typeof value === 'string'
    ? value.trim().slice(0, 120) || null
    : null;
}

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

/** Metrics explicitly present in the screenshot should survive without a web lookup. */
export function activityDetailsFromExtraction(item: ExtractedItem): ActivityDetails | null {
  const details = {
    distance_miles: normalizeDistance(item.distance_miles),
    completion_time: normalizeCompletionTime(item.completion_time),
  };
  return details.distance_miles == null && details.completion_time == null
    ? null
    : details;
}

/** Restrict web lookups to activities where route distance/time are useful. */
export function isDistanceBasedActivity(item: ExtractedItem): boolean {
  if (item.tag?.trim().toLowerCase() !== 'activity') return false;
  if (item.distance_miles != null || item.completion_time != null) return true;
  return /\b(hike|hiking|trail|trek|walk|waterfall|canyon|peak|summit|loop|outdoor|bike|biking|cycling|climb|mountain|preserve|reserve|park|forest|garden|zoo|botanical|cave|beach|lake|falls)\b/i.test(
    searchableActivityText(item),
  );
}

function normalizeDetails(value: unknown): ActivityDetails | null {
  if (value == null || typeof value !== 'object') return null;
  const candidate = value as {
    distance_miles?: unknown;
    completion_time?: unknown;
  };

  const distance = normalizeDistance(candidate.distance_miles);
  const completion = normalizeCompletionTime(candidate.completion_time);

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
  const extractedDetails = activityDetailsFromExtraction(item);
  if (!isDistanceBasedActivity(item) || !item.venue) return extractedDetails;
  if (extractedDetails?.distance_miles != null && extractedDetails.completion_time != null) {
    return extractedDetails;
  }

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
    return {
      distance_miles: extractedDetails?.distance_miles ?? details?.distance_miles ?? null,
      completion_time: extractedDetails?.completion_time ?? details?.completion_time ?? null,
    };
  } catch (err) {
    logError('gemini_activity.search_failed', err, { venue: item.venue });
    return extractedDetails;
  }
}
