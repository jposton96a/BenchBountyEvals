# Publication procedure

1. Receive a runner handoff and locate its completed raw job directory.
2. Verify the run ID, status, and exact model/agent/benchmark configuration.
3. Copy only the run artifacts into a staging directory.
4. Remove `.env`, tokens, authorization headers, cookies, private keys,
   runtime secrets, and host-specific sensitive paths. Run secret scanning.
5. Create a deterministic `tar.zst` bundle and `sha256sum` manifest (or a
   `tar.gz` fallback when zstd is unavailable).
6. Upload the bundle to a GitHub Release tagged with the immutable run ID.
7. Write normalized compact JSON with the Release URL and checksum.
8. Validate all JSON and cross-references, regenerate indexes, then push the
   static `published/` directory.
9. Enable GitHub Pages from the default branch and verify unauthenticated
   `index.json`, run JSON, and Release asset URLs.

Do not publish a failed run automatically when the handoff leaves ambiguity
about whether it is a real measurement or only setup output. Preserve failed
artifacts locally and ask for review.
