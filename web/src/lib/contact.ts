const supabaseUrl =
  import.meta.env.PUBLIC_SUPABASE_URL || 'https://bfbaqyhyxergcpsyhzcc.supabase.co';
const supabasePublishableKey =
  import.meta.env.PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  'sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI';

export type ContactSubmission = {
  source: 'web' | 'ios';
  name: string;
  email?: string | null;
  message: string;
  user_id?: string | null;
};

export async function submitContactSubmission(
  submission: ContactSubmission,
): Promise<void> {
  const response = await fetch(`${supabaseUrl}/rest/v1/contact_submissions`, {
    method: 'POST',
    headers: {
      apikey: supabasePublishableKey,
      Authorization: `Bearer ${supabasePublishableKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=minimal',
    },
    body: JSON.stringify(submission),
  });

  if (!response.ok) {
    throw new Error(`Contact submission failed (${response.status})`);
  }
}
