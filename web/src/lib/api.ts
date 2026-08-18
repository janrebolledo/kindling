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

type IdeaFetcher = {
  fetch: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
};

async function readIdea(res: Response): Promise<SharedIdea | null> {
  if (!res.ok) return null;
  return (await res.json()) as SharedIdea;
}

export async function fetchSharedIdea(
  id: string,
  boundApi?: IdeaFetcher,
): Promise<SharedIdea | null> {
  if (!/^\d+$/.test(id)) return null;
  const url = `${apiBase()}/share/${id}`;
  try {
    return await readIdea(
      await (boundApi ? boundApi.fetch(new Request(url)) : fetch(url)),
    );
  } catch (err) {
    console.error('fetchSharedIdea failed', { id, url, err });
    if (!boundApi) return null;
    try {
      return await readIdea(await fetch(url));
    } catch (fallbackErr) {
      console.error('fetchSharedIdea fallback failed', { id, url, err: fallbackErr });
      return null;
    }
  }
}
