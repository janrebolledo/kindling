import { ai } from '../';
import { parseScreenshotPrompt } from '../prompts';

async function generateWithRetry(params: Parameters<typeof ai.models.generateContent>[0], maxRetries = 5) {
  let delay = 1000;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await ai.models.generateContent(params);
    } catch (err: any) {
      const status = err?.status ?? err?.httpError?.status ?? err?.response?.status;
      if (status === 503 && attempt < maxRetries) {
        console.warn(`Gemini 503, retrying in ${delay}ms (attempt ${attempt + 1}/${maxRetries})`);
        await new Promise((res) => setTimeout(res, delay));
        delay *= 2;
        continue;
      }
      throw err;
    }
  }
  throw new Error('Unreachable');
}

export async function parseScreenshot(text: string) {
  console.log('req started');

  const response = await generateWithRetry({
    model: 'gemini-2.5-flash-lite-preview-09-2025',
    contents: parseScreenshotPrompt + text,
  });

  const data = JSON.parse(response.text || '[]') as [ExtractionResult];
  return data;
}

type ExtractionStatus = 'success' | 'skipped' | 'sensitive';

type ExtractionTag = 'activity' | 'event' | 'food';

export type ExtractionResult = {
  id: string;
  data: {
    status: ExtractionStatus;
    // explanation if skipped/sensitive, null if success
    reason: string | null;
    item: {
      name: string | null;
      venue: string | null;
      location: string | null;
      address: string | null;
      // formatted as "YYYY-MM-DD" or null
      date: string | null;
      // formatted as "HH:MM AM/PM" or null
      time: string | null;
      tag: ExtractionTag;
      activity_type: string | null;
      description: string | null;
    };
  };
};
