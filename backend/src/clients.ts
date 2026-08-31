import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export type AIRequest = {
  model: string;
  input: string;
  instructions?: string;
  reasoning?: { effort: 'none' | 'low' | 'medium' | 'high' | 'xhigh' | 'max' };
  text?: { format: Record<string, unknown> };
  tools?: Array<{ type: string }>;
};

export type AIResponse = {
  output_text?: string;
  output?: unknown[];
};

export type AIClient = {
  responses: {
    create(request: AIRequest): Promise<AIResponse>;
  };
};

export function createSupabase(env: CloudflareBindings): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_API_KEY);
}

export function createAI(env: CloudflareBindings): AIClient {
  return {
    responses: {
      async create(request) {
        const response = await fetch('https://api.openai.com/v1/responses', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${env.OPENAI_API_KEY}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(request),
        });

        if (!response.ok) {
          const error = new Error(`OpenAI request failed with status ${response.status}`);
          Object.assign(error, { status: response.status });
          throw error;
        }

        return await response.json() as AIResponse;
      },
    },
  };
}

export function getAIOutputText(response: AIResponse): string {
  if (typeof response.output_text === 'string') return response.output_text;

  return (response.output ?? [])
    .flatMap((item) => {
      if (item == null || typeof item !== 'object') return [];
      const content = (item as { content?: unknown }).content;
      if (!Array.isArray(content)) return [];
      return content.flatMap((part) => {
        if (part == null || typeof part !== 'object') return [];
        const text = (part as { text?: unknown }).text;
        return typeof text === 'string' ? [text] : [];
      });
    })
    .join('');
}
