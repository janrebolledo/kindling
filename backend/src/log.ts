function serializeError(err: unknown) {
  if (err instanceof Error) {
    return { name: err.name, message: err.message, stack: err.stack };
  }
  if (err != null && typeof err === 'object') return err;
  return { message: String(err) };
}

export function log(event: string, fields?: object) {
  console.log(
    JSON.stringify({ ts: new Date().toISOString(), event, ...fields }),
  );
}

export function logError(event: string, err: unknown, fields?: object) {
  console.error(
    JSON.stringify({
      ts: new Date().toISOString(),
      event,
      ...fields,
      error: serializeError(err),
    }),
  );
}
