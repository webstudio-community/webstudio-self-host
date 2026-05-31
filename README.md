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
| `db-setup` | Grants PostgREST permissions on DB tables (runs once) |
| `postgrest` | PostgREST — REST API over the DB |
| `migrate` | Runs Prisma migrations on startup |
| `minio` | S3-compatible object storage for assets |
| `nginx` | Serves published static sites |
| `publisher` | Generates static HTML when you click Publish |

---

## Deploy with plain Docker Compose

```bash
git clone https://github.com/webstudio-community/webstudio-self-host.git
cd webstudio-self-host

cp .env.example .env
# Edit .env — change every "change-me" value
```

Generate the required secrets:

```bash
# POSTGRES_PASSWORD
openssl rand -hex 16

# AUTH_SECRET
openssl rand -hex 32

# PGRST_JWT_SECRET (must be ≥ 64 characters)
openssl rand -hex 64

# TRPC_SERVER_API_TOKEN (shared secret between builder and publisher)
openssl rand -hex 32
```

Also set `DEPLOYMENT_URL` in your `.env` to your builder's public URL — required in production regardless of login mode:

```env
DEPLOYMENT_URL=https://webstudio.your-domain.com
```

Then start:

```bash
docker compose up -d
```

The builder is available at `http://localhost:3000`.

---

## Deploy with Coolify (recommended)

[Coolify](https://coolify.io) manages SSL certificates, the Traefik reverse proxy, and automatic restarts.

### Overview of the domain architecture

The setup uses **three domain scopes**, each with its own wildcard:

| Domain | Purpose | Service |
|--------|---------|---------|
| `webstudio.your-domain.com` | Main builder UI | `app` (Coolify-managed) |
| `*.webstudio.your-domain.com` | Canvas preview iframes (one per project) | `app` (Traefik label) |
| `*.wstdwork.your-domain.com` | Published static sites | `nginx` (Traefik label) |

The first domain is configured via Coolify's UI. The other two require **Traefik labels** in the compose file — Coolify routes based on these labels but does not manage them through its UI.

### 1 — DNS records

Create these records in your DNS provider (no proxy/CDN — orange cloud off if using Cloudflare):

| Type | Name | Content |
|------|------|---------|
| A | `webstudio.your-domain.com` | your server IP |
| A | `*.webstudio.your-domain.com` | your server IP |
| A | `*.wstdwork.your-domain.com` | your server IP |

> `wstdwork` is the subdomain prefix for published sites. You can pick any name — just
> make sure it matches `PUBLISHER_HOST` in your env and the labels in the compose file.

### 2 — Configure Traefik in Coolify

Webstudio needs wildcard TLS certificates, which require a DNS challenge. Coolify uses
Traefik as its reverse proxy — you need to add the Cloudflare resolver and the gzip
middleware to Traefik's static configuration.

In Coolify: **Server → Proxy → Configuration**

Under the `command:` block, add these lines (replace with your own email and cert resolver name):

```yaml
command:
  # ... existing Coolify args ...
  - "--certificatesresolvers.cloudflare.acme.email=you@your-domain.com"
  - "--certificatesresolvers.cloudflare.acme.storage=/traefik/acme.json"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge=true"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53"
```

Under the `environment:` block, add your Cloudflare API token:

```yaml
environment:
  - CF_DNS_API_TOKEN=your-cloudflare-api-token
```

To create a Cloudflare API token: **Cloudflare dashboard → My Profile → API Tokens →
Create Token** → use the "Edit zone DNS" template → restrict it to your domain.

Also add a dynamic config file so Traefik knows about the `gzip` middleware (referenced
in the compose labels). In Coolify: **Server → Proxy → Dynamic Configuration**, create
a new file `webstudio.yaml` with:

```yaml
http:
  middlewares:
    gzip:
      compress: {}
```

> **Important:** The resolver name `cloudflare` used in `--certificatesresolvers.cloudflare.*`
> must exactly match the value in `tls.certresolver=cloudflare` in the Traefik labels
> of the compose file. If you change one, change the other.

### 3 — Update Traefik labels in the compose file

Coolify does **not** interpolate environment variables inside Traefik labels. You must
edit `docker-compose.coolify.yml` directly and replace the placeholder domains with
your actual values before deploying.

**In the `app` service**, replace `webstudio.example.com` with your builder domain:

```yaml
# Before
- "traefik.http.routers.ws-canvas.rule=HostRegexp(`^.+[.]webstudio[.]example[.]com`)"
- "traefik.http.routers.ws-canvas.tls.domains[0].main=*.webstudio.example.com"
- "traefik.http.routers.ws-canvas.tls.domains[0].sans=webstudio.example.com"

# After (example)
- "traefik.http.routers.ws-canvas.rule=HostRegexp(`^.+[.]webstudio[.]your-domain[.]com`)"
- "traefik.http.routers.ws-canvas.tls.domains[0].main=*.webstudio.your-domain.com"
- "traefik.http.routers.ws-canvas.tls.domains[0].sans=webstudio.your-domain.com"
```

**In the `nginx` service**, replace `wstdwork.example.com` with your publish domain
(must match `PUBLISHER_HOST`):

```yaml
# Before
- "traefik.http.routers.ws-publisher.rule=HostRegexp(`^.+[.]wstdwork[.]example[.]com`)"
- "traefik.http.routers.ws-publisher.tls.domains[0].main=*.wstdwork.example.com"
- "traefik.http.routers.ws-publisher.tls.domains[0].sans=wstdwork.example.com"

# After (example)
- "traefik.http.routers.ws-publisher.rule=HostRegexp(`^.+[.]wstdwork[.]your-domain[.]com`)"
- "traefik.http.routers.ws-publisher.tls.domains[0].main=*.wstdwork.your-domain.com"
- "traefik.http.routers.ws-publisher.tls.domains[0].sans=wstdwork.your-domain.com"
```

### 4 — Create the resource in Coolify

In your Coolify project: **New resource → Docker Compose → From a Git repository**

- Repository: `https://github.com/webstudio-community/webstudio-self-host`
- Compose file: `docker-compose.coolify.yml`

Coolify auto-generates these variables — leave them as-is:
- `SERVICE_PASSWORD_DB`, `SERVICE_PASSWORD_AUTH`, `SERVICE_BASE64_64_PGRST`, `SERVICE_BASE64_64_TRPC`
- `SERVICE_FQDN_APP_3000`, `SERVICE_FQDN_MINIO_9000`, `SERVICE_URL_APP`

Set these manually in the Coolify environment:

```env
# Builder domain (used to construct canvas iframe URLs)
APP_FQDN=webstudio.your-domain.com

# Published sites domain suffix (must match the nginx Traefik label)
PUBLISHER_HOST=wstdwork.your-domain.com

# How users log in — choose one:

# Option A: simple password login (password = AUTH_SECRET value, shown in Coolify)
DEV_LOGIN=true
DEV_LOGIN_EMAIL=admin@example.com

# Option B: GitHub OAuth
# GH_CLIENT_ID=...
# GH_CLIENT_SECRET=...
# Note: DEPLOYMENT_URL is automatically set from SERVICE_URL_APP by the compose file
```

### 5 — Deploy

Click **Deploy** in Coolify. First deploy takes 2–3 min (pulls images, runs DB migrations).

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

## Authentication

Three login modes are available. Choose one and set the corresponding variables.

### Option A — Simple password login (default)

No external provider needed. Set in `.env` (plain Compose) or Coolify environment:

```env
DEV_LOGIN=true
DEV_LOGIN_EMAIL=admin@example.com
```

The password is the value of `AUTH_SECRET` (visible in Coolify under the service's environment variables).

### Option B — GitHub OAuth

1. Go to **github.com → Settings → Developer Settings → OAuth Apps → New OAuth App**
2. Fill in:
   - **Homepage URL**: `https://webstudio.your-domain.com`
   - **Authorization callback URL**: `https://webstudio.your-domain.com/auth/github/callback`
3. Copy the **Client ID** and generate a **Client Secret**
4. Remove `DEV_LOGIN` from your env, then add:

```env
GH_CLIENT_ID=your-client-id
GH_CLIENT_SECRET=your-client-secret
DEPLOYMENT_URL=https://webstudio.your-domain.com
```

> With Coolify: `DEPLOYMENT_URL` is automatically set from `SERVICE_URL_APP` by the compose file — no need to add it manually.

### Option C — Google OAuth

1. Go to **console.cloud.google.com → APIs & Services → Credentials → Create OAuth 2.0 Client ID**
2. Application type: **Web application**
3. Under **Authorized redirect URIs**, add: `https://webstudio.your-domain.com/auth/google/callback`
4. Copy the **Client ID** and **Client Secret**
5. Remove `DEV_LOGIN` from your env, then add:

```env
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
DEPLOYMENT_URL=https://webstudio.your-domain.com
```

> With Coolify: `DEPLOYMENT_URL` is automatically set from `SERVICE_URL_APP` by the compose file — no need to add it manually.

---

## Custom domains

Once a project is published you can attach any custom domain — including an **apex (root) domain** like `example.com` — via the **Publish** panel in the builder.

### Subdomain (`www.example.com`)

Standard setup: create a CNAME record pointing to your server hostname. The builder UI will show you the exact CNAME target and TXT verification record to add.

### Apex domain (`example.com`)

Apex domains cannot use a CNAME record with most DNS providers. The builder detects this and shows an **A record** instruction instead.

**DNS records to create:**

| Type | Name | Value |
|------|------|-------|
| A | `@` | your server IP |
| TXT | `_webstudio_is` | the token shown in the Publish panel |

**Steps:**

1. In the builder, open **Publish → Add a new domain** and enter `example.com`
2. The panel shows the A record and TXT record to create — copy the TXT value
3. In your DNS provider, create both records
4. Wait for DNS propagation (a few minutes to an hour), then click **Verify**
5. Publish — the site is served from `example.com` with an automatic Let's Encrypt certificate

Each apex domain is independent: multiple projects can each have their own apex domain pointing to the same server.

---

## Environment variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_PASSWORD` | ✅ | — | PostgreSQL password |
| `PGRST_JWT_SECRET` | ✅ | — | Secret for PostgREST JWT auth (≥ 64 chars) |
| `AUTH_SECRET` | ✅ | — | Session cookie signing secret |
| `APP_FQDN` | ✅ (Coolify) | — | Builder public domain (e.g. `webstudio.your-domain.com`) |
| `DEV_LOGIN` | — | — | `true` = password login using `AUTH_SECRET` as the password. |
| `DEV_LOGIN_EMAIL` | — | `admin@example.com` | Email used for dev login |
| `GH_CLIENT_ID` / `GH_CLIENT_SECRET` | — | — | GitHub OAuth |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | — | — | Google OAuth |
| `DEPLOYMENT_URL` | ✅ | — | Builder's public URL with protocol (e.g. `https://webstudio.your-domain.com`). Required in production for all login modes. Auto-set from `SERVICE_URL_APP` in Coolify. |
| `DEPLOYMENT_ENVIRONMENT` | — | — | Set to `production` automatically by both compose files. |
| `AUTH_WS_CLIENT_ID` | ✅ (prod) | — | OAuth server credential for the webstudio CLI. Any non-empty value. Auto-set in Coolify. |
| `AUTH_WS_CLIENT_SECRET` | ✅ (prod) | — | OAuth server secret for the webstudio CLI. Any strong random value. Auto-set in Coolify. |
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
