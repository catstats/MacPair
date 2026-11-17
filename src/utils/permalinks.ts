import { SITE } from 'astrowind:config';

const base = '/' + String(SITE.base ?? '/').replace(/^\/+|\/+$/g, '');

export function getAsset(path: string): string {
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/|#)/i.test(path)) return path;
  return (base === '/' ? '' : base) + '/' + path.replace(/^\/+/, '');
}

export function getPermalink(path: string): string {
  const result = getAsset(path).replace(/\/+$/, '');
  return SITE.trailingSlash ? result + '/' : result || '/';
}
