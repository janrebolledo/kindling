import { PostHog } from 'posthog-node';

type PostHogEnv = Pick<CloudflareBindings, 'POSTHOG_PROJECT_TOKEN' | 'POSTHOG_HOST'> & {
  ENVIRONMENT?: string;
};

let posthog: PostHog | undefined;

export function getPostHog(env: PostHogEnv): PostHog | undefined {
  if (posthog) return posthog;

  const token = env.POSTHOG_PROJECT_TOKEN;
  const host = env.POSTHOG_HOST;
  if (!token || !host) {
    if (env.ENVIRONMENT === 'development') {
      const missingVariable = token ? 'POSTHOG_HOST' : 'POSTHOG_PROJECT_TOKEN';
      throw new Error(
        `${missingVariable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once ${missingVariable} is configured`,
      );
    }
    return undefined;
  }

  posthog = new PostHog(token, {
    host,
    enableExceptionAutocapture: true,
    flushAt: 1,
    flushInterval: 0,
  });

  return posthog;
}
