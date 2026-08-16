import { describe, expect, test } from 'bun:test';
import app from './index';

describe('health', () => {
  test('returns ok', async () => {
    const res = await app.request('/health');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });
});

describe('GET /share/:id', () => {
  test('rejects non-numeric and non-positive ids', async () => {
    expect((await app.request('/share/abc')).status).toBe(404);
    expect((await app.request('/share/0')).status).toBe(404);
    expect((await app.request('/share/-1')).status).toBe(404);
  });
});
