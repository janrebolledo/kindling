import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { GoogleGenAI } from '@google/genai';

export function createSupabase(env: CloudflareBindings): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_API_KEY);
}

export function createAI(env: CloudflareBindings): GoogleGenAI {
  return new GoogleGenAI({ apiKey: env.GEMINI_API_KEY });
}
