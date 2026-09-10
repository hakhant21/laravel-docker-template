#!/usr/bin/env bash
set -euo pipefail

DEV_FILE="docker-compose.yml"
PROD_FILE="docker-compose.prod.yml"
SCRIPT_NAME="$(basename "$0")"
PROJECT_NAME="${SCRIPT_NAME%.*}"

die() {
  printf '\033[0;31mERROR\033[0m %s\n' "$*" >&2
  exit 1
}

log() { printf '\033[0;36m--\033[0m %s\n' "$*"; }
ok() { printf '\033[0;32mOK\033[0m %s\n' "$*"; }

resolve_env() {
  case "${1:-}" in
    dev|development|-d) echo "dev" ;;
    prod|production|-p) echo "prod" ;;
    *) die "Unknown environment: '${1:-}'. Use dev/prod or -d/-p." ;;
  esac
}

compose() {
  local env="$1"
  shift
  local compose_file="$DEV_FILE"
  local env_file=".env"
  [[ "$env" == "prod" ]] && compose_file="$PROD_FILE"
  [[ "$env" == "prod" ]] && env_file=".env.production"
  docker compose --env-file "$env_file" -f "$compose_file" -p "${PROJECT_NAME}_${env}" "$@"
}

require_docker() {
  command -v docker >/dev/null || die "docker not found"
  docker compose version >/dev/null || die "docker compose not found"
  docker info >/dev/null || die "docker daemon not running"
}

ensure_env() {
  if [[ "$1" == "dev" ]]; then
    [[ -f .env ]] || die "Missing .env"
  else
    [[ -f .env.production ]] || die "Missing .env.production"
    if ! grep -q '^ACME_EMAIL=' .env.production; then
      local email
      read -rp "Email address for Let's Encrypt certificates: " email
      [[ -n "$email" ]] || die "ACME email is required"
      printf '\nACME_EMAIL=%s\n' "$email" >> .env.production
    fi
  fi
}

help() {
  printf '%s\n' \
    "$SCRIPT_NAME - Laravel Docker Manager" \
    '' \
    "Usage: $SCRIPT_NAME <command> [dev|prod|-d|-p]" \
    '' \
    'Commands: up down restart build logs ps health shell exec artisan composer npm migrate fresh deploy backup clean help'
}

main() {
  if [[ $# -eq 0 || "$1" == "help" || "$1" == "-h" || "$1" == "--help" ]]; then
    help
    return
  fi

  local cmd="$1"
  shift

  if [[ "$cmd" == "deploy" ]]; then
    require_docker
    ensure_env "prod"
    compose prod pull
    compose prod up -d --remove-orphans
    compose prod exec -T app php artisan migrate --force
    compose prod exec -T app php artisan config:cache
    compose prod exec -T app php artisan route:cache
    compose prod exec -T app php artisan view:cache
    compose prod exec -T app php artisan event:cache
    compose prod exec -T app php artisan octane:reload || true
    compose prod exec -T horizon php artisan horizon:terminate || true
    docker image prune -f >/dev/null
    ok 'Deployed successfully'
    return
  fi

  local env
  env="$(resolve_env "${1:-dev}")"
  [[ $# -gt 0 ]] && shift
  ensure_env "$env"
  require_docker

  case $cmd in
    up) compose "$env" up -d --build ;;
    down) compose "$env" down ;;
    restart) compose "$env" restart ;;
    build) compose "$env" build --no-cache ;;
    logs) compose "$env" logs -f --tail=100 "$@" ;;
    ps|health) compose "$env" ps ;;
    shell) compose "$env" exec "${1:-app}" sh ;;
    exec) compose "$env" exec "$@" ;;
    artisan) compose "$env" exec app php artisan "$@" ;;
    composer) compose "$env" exec app composer "$@" ;;
    npm) compose "$env" exec app npm "$@" ;;
    migrate) compose "$env" exec app php artisan migrate "$@" ;;
    fresh)
      [[ "$env" == "prod" ]] && die 'Refusing to migrate:fresh in production'
      compose dev exec app php artisan migrate:fresh --seed
      ;;
    backup)
      mkdir -p backups
      compose "$env" exec -T mysql sh -c \
        'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE"' \
        > "backups/db_${env}_$(date +%Y%m%d_%H%M%S).sql"
      ;;
    clean) compose "$env" down -v --remove-orphans ;;
    *) die "Unknown command: $cmd" ;;
  esac
}

main "$@"
