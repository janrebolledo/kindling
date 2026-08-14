import { createClient } from '@supabase/supabase-js';
import { GoogleGenAI } from '@google/genai';

export const supabase = createClient(
  'https://bfbaqyhyxergcpsyhzcc.supabase.co',
  Bun.env['SUPABASE_API_KEY']!,
);

export const ai = new GoogleGenAI({
  apiKey: Bun.env['GEMINI_API_KEY'],
});
