import posthogJs from 'posthog-js';

const token = import.meta.env.PUBLIC_POSTHOG_KEY;
const host = import.meta.env.PUBLIC_POSTHOG_HOST;

if ((!token || !host) && import.meta.env.DEV) {
  const missingVariable = token ? 'PUBLIC_POSTHOG_HOST' : 'PUBLIC_POSTHOG_KEY';
  throw new Error(
    `${missingVariable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once ${missingVariable} is configured`,
  );
}

export const posthog = token && host
  ? posthogJs.init(token, {
    api_host: host,
    capture_exceptions: {
      capture_unhandled_errors: true,
      capture_unhandled_rejections: true,
      capture_console_errors: false,
    },
  })
  : undefined;
