import { execFileSync, spawnSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repo = 'catstats/MacPair';
const remote = 'https://github.com/' + repo + '.git';
const expectedUrl = 'https://catstats.github.io/MacPair/';
const env = { ...process.env, GH_PROMPT_DISABLED: '1', GH_NO_UPDATE_NOTIFIER: '1' };
const gitConfig = ['-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential'];
const git = (args, cwd = root) =>
  execFileSync('git', [...gitConfig, ...args], { cwd, env, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
const gh = (args, input) =>
  JSON.parse(execFileSync('gh', args, { cwd: root, env, input, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }));
if (git(['status', '--porcelain'])) throw new Error('Commit website source changes before publishing.');
for (const file of ['index.html', 'zh/index.html']) {
  const html = readFileSync(join(root, 'dist', file), 'utf8');
  if (!html.includes(expectedUrl) || html.includes('chatgpt.site'))
    throw new Error('Build the GitHub Pages configuration first: ' + file);
}
const sourceCommit = git(['rev-parse', 'HEAD']);
const author = { name: git(['log', '-1', '--format=%an']), email: git(['log', '-1', '--format=%ae']) };
const files = git(['ls-files', '-z']).split('\0').filter(Boolean);
const staging = mkdtempSync(join(tmpdir(), 'macpair-pages-'));
const excluded = (file) =>
  ['.openai/', '.github/', 'public/downloads/', 'qa/', '.sites-runtime/', '.sites-checkout/'].some((prefix) =>
    file.startsWith(prefix)
  );

function prepareBranch(branch) {
  const target = join(staging, branch);
  if (git(['ls-remote', '--heads', remote, 'refs/heads/' + branch])) {
    git(['clone', '--quiet', '--depth', '1', '--branch', branch, remote, target]);
    for (const file of readdirSync(target)) {
      if (file !== '.git') rmSync(join(target, file), { recursive: true, force: true });
    }
  } else {
    mkdirSync(target);
    git(['init', '--quiet', '--initial-branch=' + branch], target);
    git(['remote', 'add', 'origin', remote], target);
  }
  git(['config', 'user.name', author.name], target);
  git(['config', 'user.email', author.email], target);
  return target;
}
function publishBranch(branch, fill) {
  const target = prepareBranch(branch);
  fill(target);
  git(['add', '--all'], target);
  const changed = spawnSync('git', ['diff', '--cached', '--quiet'], { cwd: target, env }).status;
  if (changed === 1) {
    git(['commit', '--quiet', '-m', 'Publish ' + branch + ' from website ' + sourceCommit.slice(0, 12)], target);
    git(['push', '--quiet', 'origin', 'HEAD:refs/heads/' + branch], target);
  } else if (changed !== 0) {
    throw new Error('Could not inspect staged ' + branch + ' changes.');
  }
  process.stdout.write('Published ' + branch + '.\n');
}

try {
  const branch = git(['branch', '--show-current']);
  const origin = git(['remote']).split('\n').includes('origin') ? git(['remote', 'get-url', 'origin']) : '';
  if (branch === 'website-source' && [remote, 'git@github.com:' + repo + '.git'].includes(origin)) {
    git(['push', '--quiet', 'origin', 'HEAD:refs/heads/website-source']);
    process.stdout.write('Published website-source.\n');
  } else {
    publishBranch('website-source', (target) => {
      for (const file of files.filter((file) => !excluded(file))) {
        const from = join(root, file);
        if (lstatSync(from).isSymbolicLink()) throw new Error('Unexpected source symlink: ' + file);
        const to = join(target, file);
        mkdirSync(dirname(to), { recursive: true });
        cpSync(from, to);
      }
    });
  }
  publishBranch('gh-pages', (target) => {
    for (const file of readdirSync(join(root, 'dist'))) {
      if (file === 'downloads' || file === '.openai') continue;
      cpSync(join(root, 'dist', file), join(target, file), { recursive: true });
    }
    writeFileSync(join(target, '.nojekyll'), '');
  });
  let pages;
  try {
    pages = gh(['api', 'repos/' + repo + '/pages']);
  } catch (error) {
    if (!String(error.stderr).includes('404')) throw error;
    pages = gh(
      ['api', '--method', 'POST', 'repos/' + repo + '/pages', '--input', '-'],
      JSON.stringify({ build_type: 'legacy', source: { branch: 'gh-pages', path: '/' } })
    );
  }
  if (pages.source?.branch !== 'gh-pages' || pages.html_url !== expectedUrl) {
    throw new Error('Unexpected Pages configuration: ' + JSON.stringify({ url: pages.html_url, source: pages.source }));
  }
  process.stdout.write(
    JSON.stringify({
      repository: repo,
      sourceCommit,
      url: pages.html_url,
      status: pages.status,
      sourceBranch: 'website-source',
      publishedBranch: 'gh-pages',
    }) + '\n'
  );
} finally {
  if (existsSync(staging)) rmSync(staging, { recursive: true, force: true });
}
