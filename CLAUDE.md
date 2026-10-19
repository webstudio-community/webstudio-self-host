# CLAUDE.md — webstudio-self-host

Stack Docker Compose pour déployer Webstudio en auto-hébergement.

## Deux configurations

| Fichier | Cible |
|---------|-------|
| `docker-compose.yml` | Serveur Linux classique (avec Traefik externe) |
| `docker-compose.coolify.yml` | Coolify PaaS (domaines gérés par Coolify) |

## Commandes courantes

```bash
# Démarrer la stack
docker compose up -d

# Voir les logs
docker compose logs -f app
docker compose logs -f publisher

# Relancer un seul service
docker compose up -d --force-recreate app

# Mettre à jour les images
docker compose pull && docker compose up -d

# Lancer les migrations manuellement
docker compose run --rm migrate
```

## Services et dépendances

```
minio → minio-init
db → db-setup → migrate → app
                          app → nginx
                          app → publisher
```

## Variables d'environnement clés (`.env`)

```env
POSTGRES_PASSWORD=          # Requis
AUTH_SECRET=                # openssl rand -hex 32
PGRST_JWT_SECRET=           # openssl rand -hex 32
TRPC_SERVER_API_TOKEN=      # openssl rand -hex 32

PUBLISHER_HOST=             # ex: wstdwork.votre-domaine.com
BUILDER_IMAGE=              # ghcr.io/webstudio-community/builder:latest
PUBLISHER_IMAGE=            # ghcr.io/webstudio-community/webstudio-publisher:latest

# OAuth (optionnel)
GH_CLIENT_ID=
GH_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=

# Self-hosting sans auth OAuth
DEV_LOGIN=true
USER_PLAN=pro
FEATURES=*
```

## Volumes persistants

| Volume | Contenu |
|--------|---------|
| `db-data` | Données PostgreSQL |
| `minio-data` | Assets uploadés (S3) |
| `published-sites` | Sites publiés servis par Nginx |
| `publisher-work` | Répertoires de travail du publisher (node_modules, build cache) |
| `uploads` | Uploads locaux du builder |

## Points d'attention

- `db-setup` doit s'exécuter **après** `migrate` pour les tables existantes — l'ordre des `depends_on` est critique
- Le service `migrate` utilise l'image builder pour accéder au schema Prisma
- Nginx sert `/var/publish/<hostname>/` — le hostname doit correspondre exactement au domaine configuré
- Pour les custom domains avec Traefik : monter `/data/coolify/proxy/dynamic` dans le publisher et définir `TRAEFIK_DYNAMIC_DIR`
- Cibles de publication (panneau Publish, 2 sélecteurs `renderMode` × `host`) : `renderMode` ∈ `ssg`|`ssr`, `host` ∈ `local` (proxy publisher) | `cloudflare` (Pages) | `ssh` (statique rsyncé sur un serveur tiers) | `coolify` (SSR ou SSG sur un Coolify distant). `ssh` : config par site via `POST /targets/ssh-setup` sur le publisher (port `4000` non authentifié, jamais exposé ; clé chmod 600 dans `publisher-work`). `coolify` : `REGISTRY_URL`/`REGISTRY_USER`/`REGISTRY_TOKEN` sur le publisher (registre où pousser l'image — SSR = react-router, SSG = `nginx:alpine`) + `docker.sock` monté (mount commenté) + webhook de déploiement Coolify saisi par site dans le panneau Publish. Voir section « Publish targets » du README
- Les cookies de session utilisent le préfixe `__Host-` (nécessite HTTPS) — pour tester `docker-compose.yml` en local sur `http://localhost` sans TLS, définir `DEPLOYMENT_ENVIRONMENT=development`, `DEPLOYMENT_URL=http://localhost:3000` et `ALLOW_INSECURE_COOKIES=true` dans `.env` (jamais en déploiement réel)
- `DEPLOYMENT_URL` est **toujours requis**, même en dev login : `docker-compose.yml` passe la variable telle quelle (chaîne vide si absente de `.env`), et l'app refuse de démarrer sur une valeur vide ("Invalid environment variables")
- Le script d'init Postgres (rôle `anon`, schema `extensions`, `search_path`) est inliné dans `docker-compose.yml` via un bloc `configs:` (pas un fichier `postgres-init.sql` séparé) — les deux compose files sont donc chacun autonomes, utilisables sans rien d'autre que le fichier lui-même

## CI

`.github/workflows/ci.yml` (PR, push `main`, et lundi 06:00 UTC) : `lint-yaml` (yamllint, config `.yamllint.yml`), `compose-config` (`docker compose config` sur les deux compose, variables Coolify factices), `nginx` (`nginx -t`) et `images` (`.github/scripts/check-images.sh`).

- Les images tierces doivent avoir un **tag épinglé** (pas de `:latest`) ; seules les images `ghcr.io/webstudio-community/*` peuvent rester flottantes. Le script vérifie aussi que chaque image existe sur le registre en `amd64` **et** `arm64` (cible Raspberry Pi) — c'est ce qui aurait détecté le retrait de `minio/minio` (#30). Le job du lundi attrape les images retirées entre deux PR.
- La CI ne démarre pas la stack : un changement de compose reste à tester avec `docker compose up` (le bucket S3 doit être créé par `minio-init`).
- En local : `.github/scripts/check-images.sh` (Docker requis pour `compose config` et `manifest inspect`, pas de daemon nécessaire).
