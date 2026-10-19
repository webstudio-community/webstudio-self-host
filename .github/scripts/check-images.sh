#!/usr/bin/env bash
# Vérifie les images des fichiers compose :
#   1. tag épinglé (pas de :latest ni de tag absent), sauf images de l'org webstudio-community ;
#   2. image présente sur le registre, avec amd64 ET arm64 (la cible est un Raspberry Pi).
# Erreur réseau / auth : simple avertissement, pour ne pas bloquer sur une panne de registre.
set -euo pipefail
cd "$(dirname "$0")/../.."

FLOATING_ALLOWED='^ghcr\.io/webstudio-community/'
FILES=(docker-compose.yml docker-compose.coolify.yml)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errors=0

annotate() { # niveau, message
  if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::$1::$2"; else echo "$1: $2"; fi
}

images=()
for file in "${FILES[@]}"; do
  # Variables injectées au déploiement (Coolify...) : valeur factice, sauf les *_IMAGE (leur défaut est l'image à vérifier).
  grep -ohE '\$\{[A-Z_0-9]+' "$file" | sed 's/^\${//' | grep -v '_IMAGE$' | sort -u | sed 's/$/=x/' > "$tmp/env" || true
  while IFS= read -r image; do images+=("$image"); done < <(docker compose -f "$file" --env-file "$tmp/env" config --images)
done

while IFS= read -r image; do
  tag="${image##*/}"; tag="${tag#*:}"
  [ "$tag" = "${image##*/}" ] && tag=""
  if { [ -z "$tag" ] || [ "$tag" = latest ]; } && ! [[ "$image" =~ $FLOATING_ALLOWED ]]; then
    annotate error "$image : tag flottant, épingler une version précise"
    errors=$((errors + 1))
    continue
  fi

  if ! out=$(docker manifest inspect "$image" 2>&1); then
    if grep -qiE 'no such manifest|manifest unknown|name unknown|not found' <<<"$out"; then
      annotate error "$image : introuvable sur le registre (image retirée ?)"
      errors=$((errors + 1))
    else
      annotate warning "$image : registre injoignable ou accès refusé, vérification ignorée"
    fi
    continue
  fi

  if jq -e '.manifests' >/dev/null 2>&1 <<<"$out"; then
    archs=$(jq -r '[.manifests[].platform.architecture] | unique | join(",")' <<<"$out")
    for arch in amd64 arm64; do
      if ! grep -qw "$arch" <<<"${archs//,/ }"; then
        annotate error "$image : pas de build $arch (disponibles : $archs)"
        errors=$((errors + 1))
      fi
    done
  else
    annotate warning "$image : image mono-architecture, amd64/arm64 non vérifiés"
  fi
  echo "ok: $image"
done < <(printf '%s\n' "${images[@]}" | sort -u)

exit $((errors > 0))
