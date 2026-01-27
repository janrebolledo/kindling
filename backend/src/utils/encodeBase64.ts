export const encodeBase64 = async (file: File) => {
  // Convert file to ArrayBuffer then to base64
  const arrayBuffer = await file.arrayBuffer();
  const bytes = new Uint8Array(arrayBuffer);

  // Convert bytes to base64
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64 = btoa(binary);

  // Create data URL with mime type
  const dataUrl = `data:${file.type};base64,${base64}`;
  return dataUrl;
};
