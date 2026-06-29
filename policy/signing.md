# Signing policy

ArtifactX signs repository metadata. This repo does not sign individual `.rpm` or
`.deb` payloads in this feed.

Generated trees have different sensitivity:

- `repo/` is private build state. It contains `keys/private.asc` and is ignored.
- `public/` is safe static-hosting output. It contains apt/yum metadata, package
  files, and `keys/public.asc` only.
- `dist/` and selected `work/.../provenance.txt` / `archive-*-contents.txt` are
  uploadable CI artifacts and must never contain private key material.

## GitHub Actions key handling

Use GitHub-native secret controls for the stable signing key:

1. Create a GitHub Environment named `package-signing`.
2. Store the armored repository signing key as environment secrets:
   - `ARX_SIGNING_PRIVATE_ASC`
   - `ARX_SIGNING_PUBLIC_ASC`
3. Restrict the environment to protected branches, and add required reviewers if
   scheduled/manual signing should be gated.
4. Do not store the private key as a repository file, workflow variable, artifact,
   Pages asset, release asset, or cache entry.

The refresh workflow is intentionally shaped around those controls:

- Global `GITHUB_TOKEN` permissions are read-only (`contents: read`).
- The build job is attached to the `package-signing` environment and receives the
  signing secrets only for the `Build package feed` step.
- Pages deploy gets `pages: write` and `id-token: write` only in the deploy job.
- Artifact uploads are limited to `dist/`, `public/`, and selected provenance
  files from `work/`; `repo/` is never uploaded.
- `helpers/smoke-no-private-key-leak.sh` scans publishable trees before artifact
  upload and fails if `private.asc`, a PGP private-key block, or key paths appear
  in publishable outputs or package payload listings.

CI supports two modes:

1. **Product-test mode**: no signing secrets. `arx init` creates an ephemeral key
   for that run; generated artifacts are useful for structure/install smoke only.
2. **Client-stable mode**: provide the environment secrets above. The helper
   restores them into `repo/keys/` before publishing, so apt/dnf clients can keep
   trusting the same repository key across refreshes.

## GitHub repository settings

Enable GitHub Secret Protection where available:

- Secret scanning: detects committed credentials and private keys in repository
  history and collaboration surfaces.
- Push protection: blocks pushes containing detected secrets before they land in
  the repository.
- Custom/non-provider patterns: add a PGP private key pattern if the plan exposes
  it for this repository or organization.

Official references:

- GitHub Actions secure use: <https://docs.github.com/en/actions/reference/security/secure-use>
- GitHub Secret scanning: <https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning>
- GitHub Push protection: <https://docs.github.com/en/code-security/concepts/secret-security/push-protection>
- `GITHUB_TOKEN` least privilege: <https://docs.github.com/en/actions/tutorials/authenticate-with-github_token>

Never commit private keys, passphrases, generated `repo/`, or CI secrets. If a
private key is exposed, delete affected logs/artifacts, rotate the signing key,
and republish repository metadata with the new public key.
