import { ai } from '../';
import { parseScreenshotPrompt } from '../prompts';

export async function parseScreenshot(text: string) {
  console.log('req started');

  const response = await ai.models.generateContent({
    model: 'gemini-2.5-flash-lite-preview-09-2025',
    contents: parseScreenshotPrompt + text,
  });

  const data = JSON.parse(response.text || '[]') as ExtractionResult;
  return data;
}

type ExtractionStatus = 'success' | 'skipped' | 'sensitive';

type ExtractionTag = 'activity' | 'event' | 'food';

export type ExtractionResult = {
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
  };
};
