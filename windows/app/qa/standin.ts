// The development shell runs the stand-in tool in place of `song2vid.exe` (STANDIN_TOOL,
// electron/tool/index.ts), so the real-window checks (qa:typing, qa:kill, qa:crash) need no
// built tool and make no video. A run that wants another scenario passes a configuration
// (test/standin-tool.ts, STANDIN_CONFIG). Never honoured by a packaged app.
import { join } from 'node:path';
import { root } from './lib.ts';

export const standinEnv = (config?: string): Record<string, string> => ({ STANDIN_TOOL: join(root, 'test', 'standin-tool.ts'), ...(config ? { STANDIN_CONFIG: config } : {}) });
