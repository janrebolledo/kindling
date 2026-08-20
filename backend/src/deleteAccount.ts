import type { SupabaseClient, User } from '@supabase/supabase-js';

export async function userFromBearerToken(
  supabase: SupabaseClient,
  authorizationHeader: string | undefined,
): Promise<User | null> {
  const token = authorizationHeader?.startsWith('Bearer ')
    ? authorizationHeader.slice('Bearer '.length).trim()
    : '';
  if (!token) return null;

  const { data, error } = await supabase.auth.getUser(token);
  if (error || data.user == null) return null;
  return data.user;
}

export async function wipeAccount(
  supabase: SupabaseClient,
  userId: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  // Delete child rows first so collection_id / user_id FKs don't block the wipe.
  const { error: itemsError } = await supabase
    .from('collection_items')
    .delete()
    .eq('user_id', userId);
  if (itemsError) return { ok: false, message: itemsError.message };

  const { error: collectionsError } = await supabase
    .from('collections')
    .delete()
    .eq('user_id', userId);
  if (collectionsError) return { ok: false, message: collectionsError.message };

  const { error: userDataError } = await supabase
    .from('user_data')
    .delete()
    .eq('user_id', userId);
  if (userDataError) return { ok: false, message: userDataError.message };

  const { error: sharesError } = await supabase
    .from('idea_shares')
    .delete()
    .eq('user_id', userId);
  if (sharesError) return { ok: false, message: sharesError.message };

  const { error: deletionsError } = await supabase
    .from('idea_deletions')
    .delete()
    .eq('user_id', userId);
  if (deletionsError) return { ok: false, message: deletionsError.message };

  const { error: opensError } = await supabase
    .from('idea_share_opens')
    .delete()
    .eq('owner_user_id', userId);
  if (opensError) return { ok: false, message: opensError.message };

  // Hard-delete so the same Apple `sub` can create a brand-new auth user.
  // Soft-delete keeps the identity and Sign in with Apple restores the old account.
  const { error: authError } = await supabase.auth.admin.deleteUser(
    userId,
    false,
  );
  if (authError) return { ok: false, message: authError.message };

  return { ok: true };
}
