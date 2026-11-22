# CLAUDE.md — webstudio-self-host

Docker Compose stack to self-host Webstudio. User documentation: README.

| File | Target |
|------|--------|
| `docker-compose.yml` | Plain Linux server (external Traefik) |
| `docker-compose.coolify.yml` | Coolify (domains and secrets managed by Coolify) |

Each compose file is standalone: the Postgres init script is inlined in a
`configs:` block.

## Branches

Branch from `main`, open the PR against `main`.

## Pitfalls

- Startup order: `db → db-setup → migrate → app`; `db-setup` grants `anon` on
  tables that already exist, so the `depends_on` order matters.
- `migrate` uses the builder image (it ships the Prisma schema).
- `DEPLOYMENT_URL` is required even with dev login: the app refuses to start on
  an empty value.
- `__Host-` cookies need HTTPS; local plain-HTTP testing needs the three
  variables documented in `.env.example`.
- Coolify does not interpolate `${VAR}` in labels: domains are hardcoded.
- The publisher build API (port 4000) has no authentication: never expose it.
- The README anchor `#coolify-remote-ssr` is linked from the builder.

## CI

`ci.yml` (PRs, `main`, weekly): yamllint, `docker compose config` on both files
(dummy Coolify variables), `nginx -t`, and `.github/scripts/check-images.sh`.

- Third-party images need a pinned tag present for `amd64` and `arm64`; only
  `ghcr.io/webstudio-community/*` may float.
- CI never starts the stack: test compose changes with `docker compose up`.

## Comments & commits

Match upstream Webstudio: comments are rare (<1 % of lines).

- No comment by default; a clear name beats a comment. Comment only a
  non-obvious *why*: external constraint, workaround, trap, required order.
  - ✅ `// Navigation can discard Chrome's body before the next DOM poll.`
  - ❌ `// Check if any custom domains are selected` (restates the code)
- One line, plain English, present tense; three lines at most.
- JSDoc only for a non-trivial exported API or `@deprecated`; no `@param` /
  `@returns` that repeat the signature.
- Never: our own issue/PR numbers, history ("now", "used to", "fix:"), section
  banners, emojis, French, step numbering that mirrors the code. An upstream
  issue link that tells when to drop a workaround is fine.
- Config files (YAML, `.env`, Dockerfile, nginx): one line for each non-obvious
  setting.
- Commits: `type(scope): summary`, imperative, lowercase, ≤ 72 chars, English,
  one `(#n)` at most. Body: why, in short prose.
- PRs: problem, cause, fix in 1–2 paragraphs; a `- [x]` checklist of the checks
  actually run; `Closes #n` / `Ref #n` last.
