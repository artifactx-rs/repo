# Signing policy

ArtifactX signs repository metadata. This repo does not sign individual `.rpm` or
`.deb` payloads in phase one.

Generated trees have different sensitivity:

- `repo/` is private build state. It contains `keys/private.asc` and is ignored.
- `public/` is safe static-hosting output. It contains apt/yum metadata, package
  files, and `keys/public.asc` only.

CI supports two modes:

1. **Product-test mode**: no signing secrets. `arx init` creates an ephemeral key
   for that run; generated artifacts are useful for structure/install smoke only.
2. **Client-stable mode**: provide `ARX_SIGNING_PRIVATE_ASC` and
   `ARX_SIGNING_PUBLIC_ASC` secrets. The helper restores them into `repo/keys/`
   before publishing, so apt/dnf clients can keep trusting the same repository
   key across refreshes.

Never commit private keys, passphrases, generated `repo/`, or CI secrets.
