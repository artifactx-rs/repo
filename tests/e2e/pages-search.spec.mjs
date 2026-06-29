import { expect, test } from '@playwright/test';

test.describe('Pages package search', () => {
  test.beforeEach(async ({ page }) => {
    const consoleErrors = [];
    page.on('console', message => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', error => consoleErrors.push(error.message));
    await page.goto('/');
    await expect(page.getByRole('heading', { name: 'ArtifactX Packages', level: 1 })).toBeVisible();
    test.info().annotations.push({ type: 'consoleErrors', description: consoleErrors.join('\n') });
    expect(consoleErrors).toEqual([]);
  });

  test('renders the generated package catalog and repository links', async ({ page }) => {
    await expect(page.getByRole('searchbox', { name: /search by package/i })).toBeVisible();
    await expect(page.getByText('11 of 11 packages')).toBeVisible();
    await expect(page.getByText('44 package files')).toBeVisible();
    await expect(page.getByRole('link', { name: 'apt InRelease' })).toHaveAttribute('href', 'apt/dists/stable/InRelease');
    await expect(page.getByRole('link', { name: 'package catalog JSON' })).toHaveAttribute('href', 'packages.json');
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmagent' })).toBeVisible();
  });

  test('filters package cards and exposes install commands plus package links', async ({ page }) => {
    await page.getByRole('searchbox', { name: /search by package/i }).fill('vmagent');

    await expect(page.getByText('1 of 11 packages')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmagent' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'victoriametrics-vmalert' })).toHaveCount(0);
    await expect(page.getByText('sudo apt-get install victoriametrics-vmagent')).toBeVisible();
    await expect(page.getByText('sudo dnf install victoriametrics-vmagent')).toBeVisible();
    await expect(page.getByRole('link', { name: 'victoriametrics-vmagent_1.146.0_amd64.deb' })).toHaveAttribute(
      'href',
      'apt/pool/main/victoriametrics-vmagent_1.146.0_amd64.deb',
    );
    await expect(page.getByRole('link', { name: 'victoriametrics-vmagent-1.146.0-1.x86_64.rpm' })).toHaveAttribute(
      'href',
      'yum/stable/x86_64/victoriametrics-vmagent-1.146.0-1.x86_64.rpm',
    );
  });

  test('shows an empty state for unmatched searches', async ({ page }) => {
    await page.getByRole('searchbox', { name: /search by package/i }).fill('does-not-exist');

    await expect(page.getByText('0 of 11 packages')).toBeVisible();
    await expect(page.getByRole('status')).toHaveText('No packages match this search.');
  });
});
