import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import config from '../app.config.json';
import { App } from './App';
import { boot, desktop, platform } from './desktop';
import { startApp } from './state/app';
import { installWindowTracking } from './state/modality';
import { setShortcutPlatform } from './state/shortcuts';
import './styles/app.css';

installWindowTracking();
document.title = config.productName;
// The stylesheet reads this for the title bar's inset and nothing else; the
// shortcut labels read it through setShortcutPlatform.
document.documentElement.dataset.platform = platform;
setShortcutPlatform(platform);

// Everything the first screen needs is ready before the first paint, so there
// is no loading state to flash: the system, the remembered Codec, the tool's status and the
// Encoder report.
startApp(desktop, boot);

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App boot={boot} desktop={desktop} platform={platform} />
  </StrictMode>,
);
