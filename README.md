# webstudio-self-host

Docker Compose setup to self-host [Webstudio](https://webstudio.is) — the open-source visual development platform.

> **Requirements:** Linux server · Docker ≥ 24 · Compose v2 · 2 GB RAM · 10 GB disk

This repo provides two compose files:
- `docker-compose.yml` — plain Docker Compose (any Linux server)
- `docker-compose.coolify.yml` — optimised for [Coolify](https://coolify.io) with Traefik and auto-generated secrets

## What's included

| Service | Role |
|---------|------|
| `app` | Webstudio builder (Remix app) |
| `db` | PostgreSQL 15 |
| `postgrest` | PostgREST — REST API over the DB |
| `migrate` | Runs Prisma migrations on startup |
| `minio` | S3-compatible object storage for assets |
| `nginx` | Serves published static sites + proxies the builder |
| `publisher` | Generates static HTML when you click Publish |

---

## Deploy with plain Docker Compose

```bash
git clone https://github.com/webstudio-community/webstudio-self-host.git
cd webstudio-self-host

cp .env.example .env
# Edit .env — change every "change-me" value

docker compose up -d
```

The builder is then available at `http://localhost:3000`.

Generate the required secrets:

```bash
# AUTH_SECRET
openssl rand -hex 32

# PGRST_JWT_SECRET (must be ≥ 64 characters)
node -e "console.log(require('crypto').randomBytes(64).toString('hex'))"

# TRPC_SERVER_API_TOKEN (for the publisher service)
openssl rand -hex 32
```

---

## Deploy with Coolify (recommended)

[Coolify](https://coolify.io) handles SSL, reverse proxy, and restarts automatically.

### 1 — Create the service

In your Coolify project: **New resource → Docker Compose → From a Git repository**

- Repository: `https://github.com/webstudio-community/webstudio-self-host`
- Compose file: `docker-compose.coolify.yml`

### 2 — Configure domains

In the `app` service settings, set your main domain:

```
webstudio.your-domain.com
```

Canvas subdomains (`p-<id>.your-domain.com`) are routed automatically via the
Traefik labels in the compose file. You need a **wildcard DNS record**:

```
*.your-domain.com  →  your-server-IP
```

In the `nginx` service settings, set the wildcard domain for published sites:

```
*.pub.your-domain.com
```

This also requires a wildcard DNS record: `*.pub.your-domain.com → your-server-IP`.

### 3 — Update Traefik labels

The `app` and `nginx` services contain hardcoded Traefik labels (Coolify does not
interpolate variables in labels). Before deploying, edit `docker-compose.coolify.yml`
and replace the placeholder domains:

- In `app` labels: replace `webstudio.example.com` with your actual app domain
- In `nginx` labels: replace `pub.example.com` with your `PUBLISHER_HOST` value

### 4 — Set environment variables

Coolify auto-generates these — leave them as-is:
- `SERVICE_PASSWORD_DB`, `SERVICE_PASSWORD_AUTH`, `SERVICE_BASE64_64_PGRST`, `SERVICE_BASE64_64_TRPC`
- `SERVICE_FQDN_APP_3000`, `SERVICE_FQDN_MINIO_9000`, `SERVICE_FQDN_NGINX_80`

Set these manually:

```env
# How users log in — choose one:

# Option A: simple password login (password = AUTH_SECRET value)
DEV_LOGIN=true
DEV_LOGIN_EMAIL=admin@example.com

# Option B: GitHub OAuth
# GH_CLIENT_ID=...
# GH_CLIENT_SECRET=...

# Your publish domain (must match the Traefik label in nginx)
PUBLISHER_HOST=pub.your-domain.com
```

### 5 — Deploy

Click **Deploy** in Coolify. First deploy takes 2–3 min (pulls images, runs DB migrations).

---

## Wildcard SSL with Cloudflare + Coolify

To get a valid wildcard certificate for `*.your-domain.com`, Traefik needs
to solve an ACME DNS challenge via Cloudflare's API.

### 1 — Create a Cloudflare API token

In Cloudflare dashboard → **My Profile → API Tokens → Create Token**

Use the **"Edit zone DNS"** template, restrict it to your domain.

### 2 — Add DNS records (DNS only, not proxied)

| Type | Name | Content |
|------|------|---------|
| A | `your-domain.com` | your server IP |
| A | `*.your-domain.com` | your server IP |
| A | `*.pub.your-domain.com` | your server IP |

### 3 — Configure Traefik in Coolify

In Coolify → **Server → Proxy configuration**, add to Traefik's command args:

```yaml
- "--certificatesresolvers.cloudflare.acme.email=your@email.com"
- "--certificatesresolvers.cloudflare.acme.storage=/traefik/acme.json"
- "--certificatesresolvers.cloudflare.acme.dnschallenge=true"
- "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare"
- "--certificatesresolvers.cloudflare.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53"
```

And add the API token to Traefik's environment:

```yaml
environment:
  - CF_DNS_API_TOKEN=your-cloudflare-api-token
```

---

## Updating

```bash
# Docker Compose
docker compose pull
docker compose up -d

# Coolify: click "Redeploy" in the UI
```

DB migrations run automatically on every restart.

---

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_PASSWORD` | ✅ | — | PostgreSQL password |
| `PGRST_JWT_SECRET` | ✅ | — | Secret for PostgREST JWT auth (≥ 64 chars) |
| `AUTH_SECRET` | ✅ | — | Session cookie signing secret |
| `DEV_LOGIN` | — | — | `true` = password login (password = `AUTH_SECRET`) |
| `DEV_LOGIN_EMAIL` | — | `admin@example.com` | Email for dev login |
| `GH_CLIENT_ID` / `GH_CLIENT_SECRET` | — | — | GitHub OAuth |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | — | — | Google OAuth |
| `PUBLISHER_HOST` | — | `wstd.work` | Domain suffix for published project URLs |
| `TRPC_SERVER_API_TOKEN` | — | — | Service token shared between builder and publisher |
| `SELF_HOSTED_PUBLISHER_URL` | — | `http://publisher:4000` | Internal publisher URL |
| `FEATURES` | — | `*` | Feature flags (`*` = all enabled) |
| `USER_PLAN` | — | `pro` | Plan level for all users |
| `MAX_ASSETS_PER_PROJECT` | — | `50` | Asset upload limit per project |
| `S3_ENDPOINT` / `S3_REGION` / `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` / `S3_BUCKET` | — | MinIO defaults | S3-compatible storage |
| `ENTRI_APPLICATION_ID` / `ENTRI_SECRET` | — | — | Entri automatic DNS setup (optional) |
| `BUILDER_IMAGE` | — | `ghcr.io/webstudio-community/builder:latest` | Builder Docker image |
| `PUBLISHER_IMAGE` | — | `ghcr.io/webstudio-community/webstudio-publisher:latest` | Publisher Docker image |

---

## Related repositories

- [webstudio-fork](https://github.com/webstudio-community/webstudio-fork) — builder with self-hosting patches, Docker image CI
- [webstudio-publisher](https://github.com/webstudio-community/webstudio-publisher) — publisher service source and Docker image CI
