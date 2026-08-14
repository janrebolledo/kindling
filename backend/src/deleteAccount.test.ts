import { describe, expect, test } from 'bun:test';
import { userFromBearerToken, wipeAccount } from './deleteAccount';

describe('userFromBearerToken', () => {
  test('returns null without a bearer token', async () => {
    const supabase = {
      auth: {
        getUser: async () => ({ data: { user: null }, error: null }),
      },
    };

    expect(await userFromBearerToken(supabase as never, undefined)).toBeNull();
    expect(await userFromBearerToken(supabase as never, 'Basic abc')).toBeNull();
    expect(await userFromBearerToken(supabase as never, 'Bearer')).toBeNull();
    expect(await userFromBearerToken(supabase as never, 'Bearer   ')).toBeNull();
  });

  test('returns the user when getUser succeeds', async () => {
    const user = { id: 'u1' };
    const supabase = {
      auth: {
        getUser: async (jwt: string) => {
          expect(jwt).toBe('tok');
          return { data: { user }, error: null };
        },
      },
    };

    expect(await userFromBearerToken(supabase as never, 'Bearer tok')).toEqual(
      user,
    );
  });

  test('returns null when getUser errors', async () => {
    const supabase = {
      auth: {
        getUser: async () => ({
          data: { user: null },
          error: { message: 'invalid' },
        }),
      },
    };

    expect(
      await userFromBearerToken(supabase as never, 'Bearer tok'),
    ).toBeNull();
  });
});

describe('wipeAccount', () => {
  function mockSupabase(options?: {
    failTable?: string;
    failAuth?: boolean;
  }) {
    const calls: string[] = [];
    const supabase = {
      from: (table: string) => ({
        delete: () => ({
          eq: async (col: string, val: string) => {
            calls.push(`${table}:${col}:${val}`);
            if (options?.failTable === table) {
              return { error: { message: `${table} failed` } };
            }
            return { error: null };
          },
        }),
      }),
      auth: {
        admin: {
          deleteUser: async (id: string, shouldSoftDelete: boolean) => {
            calls.push(`auth:${id}:${shouldSoftDelete}`);
            if (options?.failAuth) {
              return { error: { message: 'auth delete failed' } };
            }
            return { error: null };
          },
        },
      },
      calls,
    };
    return supabase;
  }

  test('deletes items, collections, user_data, then hard-deletes the auth user', async () => {
    const supabase = mockSupabase();
    const result = await wipeAccount(supabase as never, 'user-1');
    expect(result).toEqual({ ok: true });
    expect(supabase.calls).toEqual([
      'collection_items:user_id:user-1',
      'collections:user_id:user-1',
      'user_data:user_id:user-1',
      'auth:user-1:false',
    ]);
  });

  test('stops before deleting the auth user if owned rows fail', async () => {
    const supabase = mockSupabase({ failTable: 'collections' });
    const result = await wipeAccount(supabase as never, 'user-1');
    expect(result).toEqual({ ok: false, message: 'collections failed' });
    expect(supabase.calls).toEqual([
      'collection_items:user_id:user-1',
      'collections:user_id:user-1',
    ]);
  });

  test('returns the auth error when hard-delete fails', async () => {
    const supabase = mockSupabase({ failAuth: true });
    const result = await wipeAccount(supabase as never, 'user-1');
    expect(result).toEqual({ ok: false, message: 'auth delete failed' });
  });
});
