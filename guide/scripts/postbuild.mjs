// After `astro build`: serve the guide home at /guide with no redirect hop (WS6 4.3).
// Cloudflare Pages serves guide/index.html at /guide/ and redirects /guide there; a flat
// guide.html beside the folder is served at /guide directly. Asset URLs are absolute.
import { existsSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const website = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'website');
const from = join(website, 'guide', 'index.html');
if (!existsSync(from)) {
  console.error('postbuild: website/guide/index.html is missing');
  process.exit(1);
}
renameSync(from, join(website, 'guide.html'));
