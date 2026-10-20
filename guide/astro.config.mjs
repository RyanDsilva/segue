// Segue user guide (docs/release/specs/WS6-user-guide.md). Builds into ../website/guide,
// which Cloudflare Pages publishes with the rest of website/ (scripts/pages-build.sh).
import starlight from '@astrojs/starlight';
import { defineConfig } from 'astro/config';
import starlightLinksValidator from 'starlight-links-validator';
import { satteri } from '@astrojs/markdown-satteri';

/** The sidebar: the musician's workflow (R55), then settings and reference. Flat URLs. */
const page = (slug, label) => ({ slug, label });
const sidebar = [
  {
    label: 'Start here',
    items: [page('index', 'Getting started'), page('welcome-library', 'Welcome library'), page('library-folder', 'Library folder')],
  },
  {
    label: 'Bring songs in',
    items: [page('paste-a-song', 'Paste a song'), page('import-files', 'Import files'), page('new-song', 'Start from scratch')],
  },
  {
    label: 'Make each chart yours',
    items: [
      page('song-card', 'Song card'),
      page('edit-a-song', 'Edit a song'),
      page('sections', 'Sections'),
      page('section-notes', 'Section notes'),
      page('text-mode', 'Text mode'),
      page('transpose', 'Transpose and capo'),
    ],
  },
  {
    label: 'Build the set',
    items: [
      page('build-a-set', 'Build a set'),
      page('set-assistant', 'Set assistant'),
      page('running-time', 'Running time'),
      page('arrange-sections', 'Arrange sections'),
      page('smart-filters', 'Smart filters'),
    ],
  },
  {
    label: 'Play the show',
    items: [
      page('go-on-stage', 'Go on stage'),
      page('requests', 'Requests'),
      page('metronome', 'Metronome'),
      page('rehearse', 'Rehearse'),
      page('gig-mode', 'Gig Mode Shortcuts'),
      page('gig-log', 'Gig log'),
    ],
  },
  {
    label: 'Settings and data',
    items: [page('ai', 'AI'), page('privacy-settings', 'Privacy'), page('back-up', 'Back up and restore')],
  },
  { label: 'Reference', items: [page('keyboard', 'Keyboard shortcuts'), page('troubleshooting', 'Troubleshooting')] },
];

export default defineConfig({
  site: 'https://segue.ryandsilva.dev',
  base: '/guide',
  outDir: '../website/guide',
  trailingSlash: 'never',
  // Heading attributes give stable ids the app deep-links to (WS6 2.1):
  // `## Remove the Welcome songs {#remove}` renders <h2 id="remove">.
  markdown: {
    processor: satteri({ features: { headingAttributes: true } }),
    // Plain code blocks: the highlighter writes style attributes the guide CSP blocks.
    syntaxHighlight: false,
  },
  build: { format: 'preserve', inlineStylesheets: 'never' },
  vite: { build: { assetsInlineLimit: 0 } },
  integrations: [
    starlight({
      title: 'Segue Guide',
      description: 'How to use Segue for Mac: bring your songs in, make each chart yours, build the set, play the show.',
      disable404Route: true,
      pagefind: true,
      expressiveCode: false,
      lastUpdated: false,
      tableOfContents: false,
      favicon: '/favicon.svg',
      customCss: ['./src/styles/guide.css'],
      sidebar,
      components: {
        Head: './src/components/overrides/Head.astro',
        ThemeProvider: './src/components/overrides/ThemeProvider.astro',
        ThemeSelect: './src/components/overrides/ThemeSelect.astro',
        SiteTitle: './src/components/overrides/SiteTitle.astro',
        Footer: './src/components/overrides/Footer.astro',
        Search: './src/components/overrides/Search.astro',
        Sidebar: './src/components/overrides/Sidebar.astro',
        PageTitle: './src/components/overrides/PageTitle.astro',
        MobileMenuToggle: './src/components/overrides/MobileMenuToggle.astro',
      },
      plugins: [
        starlightLinksValidator({
          errorOnRelativeLinks: true,
          errorOnLocalLinks: true,
          // Site pages outside the guide; gen-site.swift --check resolves these.
          exclude: ['/privacy', '/privacy#*', '/support', '/support#*', '/changelog', '/feedback', '/'],
        }),
      ],
    }),
  ],
});
