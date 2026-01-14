import { Stack } from 'expo-router';
import './global.css';

import { useFonts } from 'expo-font';
import * as SplashScreen from 'expo-splash-screen';
import { useEffect } from 'react';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({
    'PPNeueMontreal-Medium': require('../assets/fonts/PPNeueMontreal-Medium.otf'),
    'PPEditorialNew-Regular': require('../assets/fonts/PPEditorialNew-Regular.otf'),
    'PPEditorialNew-Italic': require('../assets/fonts/PPEditorialNew-Italic.otf'),
  });
  useEffect(() => {
    if (loaded || error) {
      SplashScreen.hideAsync();
    }
  }, [loaded, error]);

  if (!loaded && !error) {
    return null;
  }
  return <Stack />;
}
