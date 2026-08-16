export type SharedIdea = {
  id: number;
  name: string | null;
  type: string | null;
  description: string | null;
  media_url: string | null;
  address: string | null;
  location: string | null;
  location_type: string | null;
  duration: string | null;
  venue: string | null;
  place_id: string | null;
  open_hours: string[] | null;
  created_at: string;
};

const DEFAULT_API_URL = 'https://api.getkindl.ing';

export function apiBase(): string {
  const fromEnv = import.meta.env.PUBLIC_API_URL as string | undefined;
  return fromEnv && fromEnv.length > 0
    ? fromEnv.replace(/\/$/, '')
    : DEFAULT_API_URL;
}

export async function fetchSharedIdea(
  id: string,
): Promise<SharedIdea | null> {
  if (!/^\d+$/.test(id)) return null;
  const res = await fetch(`${apiBase()}/share/${id}`);
  if (!res.ok) return null;
  return (await res.json()) as SharedIdea;
}
