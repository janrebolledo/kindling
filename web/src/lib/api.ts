export type SharedIdea = {
  id: number;
  name: string | null;
  type: string | null;
  description: string | null;
  media_url: string | null;
  location_type: string | null;
  location_emoji: string | null;
  duration: string | null;
  place_id: string | null;
  date: string | null;
  time: string | null;
  created_at: string;
};

const SHARE_URL = 'https://api.getkindl.ing/share';

export async function fetchSharedIdea(
  api: Fetcher,
  id: string,
): Promise<SharedIdea | null> {
  if (!/^\d+$/.test(id)) return null;
  const res = await api.fetch(new Request(`${SHARE_URL}/${id}`));
  if (res.status === 404) return null;
  if (!res.ok) {
    throw new Error(`GET /share/${id} failed (${res.status})`);
  }
  return (await res.json()) as SharedIdea;
}
