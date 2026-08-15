export type OpenStatus = {
  isOpen: boolean;
  detail: string;
};

const timeRegex = /\d{1,2}(?::\d{2})?\s*[AaPp][Mm]/g;
const dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

function extractTimes(str: string): { open: string; close: string } | null {
  const matches = str.match(timeRegex);
  if (!matches || matches.length < 2) return null;
  return { open: matches[0], close: matches[matches.length - 1] };
}

function parseTime(s: string, now: Date): Date | null {
  const trimmed = s.trim();
  const match = trimmed.match(/^(\d{1,2})(?::(\d{2}))?\s*([AaPp])[Mm]$/);
  if (!match) return null;
  let hour = Number(match[1]);
  const minute = Number(match[2] ?? '0');
  const mer = match[3].toUpperCase();
  if (mer === 'P' && hour < 12) hour += 12;
  if (mer === 'A' && hour === 12) hour = 0;
  const d = new Date(now);
  d.setHours(hour, minute, 0, 0);
  return d;
}

function toMinutes(d: Date): number {
  return d.getHours() * 60 + d.getMinutes();
}

/** Mirrors the iOS `resolveOpenStatus` helper. */
export function resolveOpenStatus(openHours: string[], now = new Date()): OpenStatus | null {
  const weekday = now.getDay();
  const todayName = dayNames[weekday];
  const entry = openHours.find((row) => row.startsWith(todayName));
  if (!entry) return null;
  const colon = entry.indexOf(': ');
  if (colon < 0) return null;
  const hoursStr = entry.slice(colon + 2).trim();

  if (hoursStr.toLowerCase() === 'open 24 hours') {
    return { isOpen: true, detail: 'Open 24 hours' };
  }

  const nowMin = toMinutes(now);

  if (hoursStr.toLowerCase() !== 'closed') {
    for (const period of hoursStr.split(', ')) {
      const times = extractTimes(period);
      if (!times) continue;
      const openTime = parseTime(times.open, now);
      const closeTime = parseTime(times.close, now);
      if (!openTime || !closeTime) continue;
      const openMin = toMinutes(openTime);
      let closeMin = toMinutes(closeTime);
      if (closeMin <= openMin) closeMin += 1440;
      if (nowMin >= openMin && nowMin < closeMin) {
        return { isOpen: true, detail: `Closes at ${times.close}` };
      }
      if (nowMin < openMin) {
        return { isOpen: false, detail: `Opens at ${times.open}` };
      }
    }
  }

  for (let daysAhead = 1; daysAhead <= 6; daysAhead++) {
    const nextName = dayNames[(weekday + daysAhead) % 7];
    const nextEntry = openHours.find((row) => row.startsWith(nextName));
    if (!nextEntry) continue;
    const nextColon = nextEntry.indexOf(': ');
    if (nextColon < 0) continue;
    const nextHours = nextEntry.slice(nextColon + 2).trim();
    if (nextHours.toLowerCase() === 'closed') continue;
    if (nextHours.toLowerCase() === 'open 24 hours') {
      const dayLabel = daysAhead === 1 ? '' : `${nextName} `;
      return { isOpen: false, detail: `Opens ${dayLabel}24 hours` };
    }
    const times = extractTimes(nextHours);
    if (times) {
      const dayLabel = daysAhead === 1 ? '' : `${nextName} `;
      return { isOpen: false, detail: `Opens ${dayLabel}at ${times.open}` };
    }
  }

  return { isOpen: false, detail: 'Closed' };
}

export function formatSavedOn(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

export function mapsQuery(venue: string | null, location: string | null, address: string | null): string {
  return [venue, location || address].filter(Boolean).join(' ');
}
