# Upstream synchronization

The daily workflow checks Tailscale's latest stable GitHub release and, if newer than the pinned version, resolves the tag to its commit and edits only `profiles/safe.env`, `profiles/small.env` and `profiles/extreme.env`.

No Tailscale source is vendored or forked. All builds download the pinned upstream tag/commit and reject mismatches.

The update is offered as a PR, not an auto-merge. CI must pass; hardware tests must be repeated for any new version. In addition, update the documented size benchmarks. A new tag does not trigger automatic router deployment.

If GitHub rejects the PR action, the repository may need Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests, or a separately authorized GitHub App. Do not place personal tokens in source.
