/** The URL a guide page is served at: no `.html`, no `/index`, no trailing slash. */
export const servedPath = (path: string) =>
  path.replace(/\/index(\.html)?$/, '').replace(/\.html$/, '').replace(/(.)\/$/, '$1');

/**
 * Whether a sidebar link is the current page. Starlight's `isCurrent` misses the guide home
 * (built as index.html, served at /guide), so compare served paths too.
 */
export const isCurrentLink = (link: { href: string; isCurrent: boolean }, pathname: string) =>
  link.isCurrent || servedPath(link.href) === servedPath(pathname);
