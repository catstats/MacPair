# MacPair website

The English and Simplified Chinese MacPair website, built from AstroWind, Astro 7 and Tailwind CSS 4.

- English: https://catstats.github.io/MacPair/
- 简体中文: https://catstats.github.io/MacPair/zh/
- App source and releases: https://github.com/catstats/MacPair
- Website source: the website-source branch of the same repository.
- Published static files: the gh-pages branch.

## Develop

Requires Node.js 22.23.4 or later (Node 24 recommended) and npm 10.8.2 or later.

    npm ci
    npm run dev
    npm run check
    npm run build

Open http://localhost:4321/MacPair/. Astro runs its development server in the background; use npm run dev -- status, logs or stop to manage it. The checkout uses polling for iCloud Drive.

Site origin and base are configured in src/config.yaml. All local page and public-asset URLs use src/utils/permalinks.ts. Canonical and language-alternate links include /MacPair/. English and Chinese use the same page component and typed copy.

## Publish to GitHub Pages

After checks, build and commit the website changes, then run:

    npm run deploy:pages

The publisher uses an existing GitHub CLI login with write access to catstats/MacPair. It publishes clean source to website-source and the existing dist output to gh-pages, preserving branch history without force pushes. It configures Pages to serve that branch. The app's main branch and release tags are not changed.

Source exports exclude legacy hosting metadata, runtime credentials, local QA, dependency folders and binary download mirrors. The website requires no backend. App downloads go directly to the verified GitHub Release.

## Content and verification

src/data/copy.ts contains both languages, accessibility labels and demo messages. src/data/product.ts contains the actual release URLs and archive size. The Extend/Mirror visualization is an illustration. App screenshots are component renders from the native build with an example pairing code.

Browser QA covers both languages, the base path, mode tabs, keyboard controls, window transfer, app screenshots, responsive widths and download links. Keep the earlier different-Wi-Fi user result distinct from standalone operation and the current build's pending physical two-Mac retest.

MacPair application/source licensing remains GPL-3.0-only. AstroWind's MIT notice is preserved in LICENSE.md and public/licenses. The system-font design has no analytics, external fonts, blog or newsletter.
