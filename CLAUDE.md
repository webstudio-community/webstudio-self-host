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
