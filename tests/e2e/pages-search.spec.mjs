import { expect, test } from '@playwright/test';

test.describe('Pages package search', () => {
  test.beforeEach(async ({ page }) => {
    const consoleErrors = [];
    page.on('console', message => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', error => consoleErrors.push(error.message));
    await page.goto('./');
    await expect(page.getByRole('heading', { name: 'ArtifactX Packages', level: 1 })).toBeVisible();
    test.info().annotations.push({ type: 'consoleErrors', description: consoleErrors.join('\n') });
    expect(consoleErrors).toEqual([]);
  });

  test('renders the generated package catalog and repository links', async ({ page }) => {
    await expect(page.getByRole('searchbox', { name: /search by package/i })).toBeVisible();
    await expect(page.getByText('11 of 11 packages')).toBeVisible();
    await expect(page.getByText('44 package files')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'One-click repository setup' })).toBeVisible();
    await expect(page.getByText(/curl -fsSL .*install\.sh \| sudo bash/)).toBeVisible();
    await expect(page.locator('#setup-command')).not.toContainText('-s --');
    await expect(page.getByRole('button', { name: 'Copy one-click setup command' })).toBeVisible();
    const expectedAptInRelease = await page.evaluate(() => window.repoUrl('apt/dists/stable/InRelease'));
    const expectedSetupScript = await page.evaluate(() => window.repoUrl('install.sh'));
    const expectedCatalog = await page.evaluate(() => window.repoUrl('packages.json'));
    await expect(page.getByRole('link', { name: 'apt InRelease' })).toHaveAttribute('href', expectedAptInRelease);
    await expect(page.getByRole('link', { name: 'one-click setup script' })).toHaveAttribute('href', expectedSetupScript);
    await expect(page.getByRole('link', { name: 'package catalog JSON' })).toHaveAttribute('href', expectedCatalog);
    await expect(page.getByRole('heading', { name: 'Single-node (vmsingle)' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Cluster components (vmcluster)' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Utilities' })).toBeVisible();
    const groupOrder = await page.locator('[data-package-group]').evaluateAll(groups => groups.map(group => group.dataset.packageGroup));
    expect(groupOrder).toEqual([
      'single',
      'cluster',
      'vmutils',
    ]);
    await expect(page.locator('[data-package-group="single"]').getByRole('heading', { name: /^victoriametrics$/ })).toBeVisible();
    await expect(page.locator('[data-package-group="cluster"]').getByRole('heading', { name: 'victoriametrics-vminsert' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmagent' })).toBeVisible();
  });

  test('copies the one-click setup command', async ({ page }) => {
    await page.getByRole('button', { name: 'Copy one-click setup command' }).click();

    await expect(page.getByRole('status')).toHaveText('Copied repository setup command.');
  });

  test('normalizes GitHub Pages project URLs for setup commands', async ({ page }) => {
    const urls = await page.evaluate(() => {
      const canonicalBase = window.repoBaseFromLocation('https://artifactx-rs.github.io/repo');
      return {
        githubPagesBases: [
          canonicalBase,
          window.repoBaseFromLocation('https://artifactx-rs.github.io/repo/'),
          window.repoBaseFromLocation('https://artifactx-rs.github.io/repo/index.html'),
          window.repoBaseFromLocation('https://artifactx-rs.github.io/repo/packages.json'),
        ],
        currentBase: window.repoBase,
        currentCatalog: window.repoUrl('packages.json'),
        expectedCurrentCatalog: new URL('packages.json', window.repoBase).href,
        canonicalSetupScript: new URL('install.sh', canonicalBase).href,
        canonicalCatalog: new URL('packages.json', canonicalBase).href,
      };
    });

    expect(urls.githubPagesBases).toEqual([
      'https://artifactx-rs.github.io/repo/',
      'https://artifactx-rs.github.io/repo/',
      'https://artifactx-rs.github.io/repo/',
      'https://artifactx-rs.github.io/repo/',
    ]);
    expect(urls.currentBase).toMatch(/\/$/);
    expect(urls.currentCatalog).toBe(urls.expectedCurrentCatalog);
    expect(urls.canonicalSetupScript).toBe('https://artifactx-rs.github.io/repo/install.sh');
    expect(urls.canonicalCatalog).toBe('https://artifactx-rs.github.io/repo/packages.json');
  });

  test('filters the package-name list without per-package install commands', async ({ page }) => {
    await page.getByRole('searchbox', { name: /search by package/i }).fill('vmagent');

    await expect(page.getByText('1 of 11 packages')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Utilities' })).toBeVisible();
    await expect(page.locator('[data-package-group="single"]')).toHaveCount(0);
    await expect(page.locator('[data-package-group="cluster"]')).toHaveCount(0);
    await expect(page.locator('[data-package-group="vmutils"]').getByRole('heading', { name: 'victoriametrics-vmagent' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmagent' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmalert' })).toHaveCount(0);
    await expect(page.getByText('sudo apt-get install victoriametrics-vmagent')).toHaveCount(0);
    await expect(page.getByText('sudo dnf install victoriametrics-vmagent')).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'victoriametrics-vmagent_1.146.0_amd64.deb' })).toHaveCount(0);
  });

  test('shows an empty state for unmatched searches', async ({ page }) => {
    await page.getByRole('searchbox', { name: /search by package/i }).fill('does-not-exist');

    await expect(page.getByText('0 of 11 packages')).toBeVisible();
    await expect(page.locator('#results').getByRole('status')).toHaveText('No packages match this search.');
  });
});
