import { Asset } from 'expo-asset';

export async function clickington(image: any) {
  const [asset] = await Asset.loadAsync(image);
  const uri = asset.localUri;
  const formData = new FormData();
  // @ts-ignore
  formData.append('file', { uri, name: 'chat.png', type: 'image/png' }); // Can append files (Blobs)
  formData.append('meta', JSON.stringify({ source: 'expo', at: Date.now() }));

  const response = await fetch('http://192.168.50.40:3000/', { method: 'POST', body: formData });
  const data = await response.json();
  console.log(data);
}
