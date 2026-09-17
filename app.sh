#!/usr/bin/env bash

set -euo pipefail

DEV_FILE="docker-compose.yml"
PROD_FILE="docker-compose.prod.yml"

SCRIPT_NAME="$(basename "$0")"
PROJECT_NAME="${SCRIPT_NAME%.*}"

# Runtime architecture information.
HOST_MACHINE=""
HOST_ARCH=""
HOST_BITS=""
DOCKER_ARCH=""
DOCKER_PLATFORM=""

die() {
  printf '\033[0;31mERROR\033[0m %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\033[0;36m--\033[0m %s\n' "$*"
}

warn() {
  printf '\033[0;33mWARN\033[0m %s\n' "$*"
}

ok() {
  printf '\033[0;32mOK\033[0m %s\n' "$*"
}

resolve_env() {
  case "${1:-}" in
    dev|development|-d)
      echo "dev"
      ;;
    prod|production|-p)
      echo "prod"
      ;;
    *)
      die "Unknown environment: '${1:-}'. Use dev/prod or -d/-p."
      ;;
  esac
}

detect_architecture() {
  HOST_MACHINE="$(uname -m 2>/dev/null || echo unknown)"

  if command -v dpkg >/dev/null 2>&1; then
    HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
  else
    HOST_ARCH="$HOST_MACHINE"
  fi

  if command -v getconf >/dev/null 2>&1; then
    HOST_BITS="$(getconf LONG_BIT 2>/dev/null || echo unknown)"
  else
    case "$HOST_MACHINE" in
      aarch64|arm64|x86_64|amd64)
        HOST_BITS="64"
        ;;
      *)
        HOST_BITS="32"
        ;;
    esac
  fi

  DOCKER_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"

  case "$HOST_ARCH:$HOST_BITS" in

    armhf:32|arm:32)
      DOCKER_PLATFORM="linux/arm/v7"
      ;;

    arm64:64|aarch64:64)
      DOCKER_PLATFORM="linux/arm64"
      ;;

    amd64:64|x86_64:64)
      DOCKER_PLATFORM="linux/amd64"
      ;;

    *)
      case "$DOCKER_ARCH" in
        aarch64|arm64)
          DOCKER_PLATFORM="linux/arm64"
          ;;
        arm|armv7l)
          DOCKER_PLATFORM="linux/arm/v7"
          ;;
        x86_64|amd64)
          DOCKER_PLATFORM="linux/amd64"
          ;;
        *)
          DOCKER_PLATFORM=""
          ;;
      esac
      ;;
  esac
}

configure_platform() {
  detect_architecture

  log "Machine architecture : $HOST_MACHINE"
  log "Userspace architecture: $HOST_ARCH"
  log "Userspace bits        : $HOST_BITS"
  log "Docker architecture   : $DOCKER_ARCH"

  #
  # Important:
  #
  # aarch64 kernel + armhf userspace is still a 32-bit userspace.
  #
  # Example:
  #
  #   uname -m                  -> aarch64
  #   dpkg --print-architecture -> armhf
  #   getconf LONG_BIT          -> 32
  #
  # In that case Docker images must support 32-bit ARM.
  #
  if [[ "$HOST_ARCH" == "armhf" || "$HOST_BITS" == "32" ]]; then

    export DOCKER_DEFAULT_PLATFORM="linux/arm/v7"

    #
    # Modern MariaDB/MySQL images generally do not support arm32.
    # Fall back to SQLite for this POS installation.
    #
    export USE_SQLITE=1
    export DB_CONNECTION=sqlite
    export DB_DATABASE=/app/database/database.sqlite

    mkdir -p src/database
    touch src/database/database.sqlite

    warn "32-bit ARM userspace detected."
    warn "Kernel may be aarch64, but userspace is ${HOST_ARCH}/${HOST_BITS}-bit."
    warn "Using Docker platform: linux/arm/v7"
    warn "Using SQLite because modern MariaDB/MySQL images do not support this platform."

    return
  fi

  #
  # 64-bit ARM
  #
  if [[ "$DOCKER_PLATFORM" == "linux/arm64" ]]; then
    export DOCKER_DEFAULT_PLATFORM="linux/arm64"

    log "64-bit ARM detected."
    log "Docker platform: linux/arm64"

    return
  fi

  #
  # x86_64
  #
  if [[ "$DOCKER_PLATFORM" == "linux/amd64" ]]; then
    export DOCKER_DEFAULT_PLATFORM="linux/amd64"

    log "64-bit x86 detected."
    log "Docker platform: linux/amd64"

    return
  fi

  warn "Unknown architecture."
  warn "Docker will choose the platform automatically."
}

compose() {
  local env="$1"
  shift

  local compose_file="$DEV_FILE"
  local env_file=".env"
  local server="${APP_SERVER:-fpm}"

  if [[ "$env" == "prod" ]]; then
    compose_file="$PROD_FILE"
    env_file=".env.production"
  fi

  local -a compose_args=(
    --env-file "$env_file"
    -f "$compose_file"
  )

  local -a profile_args=(
    --profile "$server"
  )

  #
  # Octane override.
  #
  if [[ "$server" == "octane" ]]; then
    compose_args+=(
      -f "${compose_file%.yml}.octane.yml"
    )
  fi

  #
  # Database selection.
  #
  if [[ "${USE_SQLITE:-0}" == "1" ]]; then
    compose_args+=(
      -f docker-compose.sqlite.yml
    )

    profile_args+=(
      --profile sqlite
    )
  else
    #
    # Keep the filename if you already use docker-compose.mysql.yml.
    #
    # It can contain MariaDB even though the filename says mysql.
    #
    compose_args+=(
      -f docker-compose.mysql.yml
    )

    profile_args+=(
      --profile mysql
    )
  fi

  docker compose \
    "${compose_args[@]}" \
    "${profile_args[@]}" \
    -p "${PROJECT_NAME}_${env}" \
    "$@"
}

require_docker() {
  command -v docker >/dev/null 2>&1 \
    || die "docker not found"

  docker compose version >/dev/null 2>&1 \
    || die "docker compose not found"

  docker info >/dev/null 2>&1 \
    || die "docker daemon not running"

  configure_platform
}

ensure_env() {
  if [[ "$1" == "dev" ]]; then

    [[ -f .env ]] \
      || die "Missing .env"

  else

    [[ -f .env.production ]] \
      || die "Missing .env.production"

    if ! grep -q '^ACME_EMAIL=' .env.production; then
      local email

      read -rp "Email address for Let's Encrypt certificates: " email

      [[ -n "$email" ]] \
        || die "ACME email is required"

      printf '\nACME_EMAIL=%s\n' "$email" >> .env.production
    fi
  fi
}

choose_server() {
  local env="$1"
  local env_file=".env"

  [[ "$env" == "prod" ]] \
    && env_file=".env.production"

  APP_SERVER="$(
    grep '^APP_SERVER=' "$env_file" \
      | cut -d= -f2- \
      || true
  )"

  if [[ "$APP_SERVER" != "fpm" && "$APP_SERVER" != "octane" ]]; then

    printf '%s\n' \
      'Choose application server:' \
      '1) PHP-FPM + Nginx (default)' \
      '2) Laravel Octane'

    local choice

    read -rp 'Selection [1]: ' choice

    case "${choice:-1}" in
      1)
        APP_SERVER="fpm"
        ;;
      2)
        APP_SERVER="octane"
        ;;
      *)
        die "Invalid server selection"
        ;;
    esac

    printf '\nAPP_SERVER=%s\n' "$APP_SERVER" >> "$env_file"
  fi

  export APP_SERVER
}

show_arch() {
  require_docker

  printf '\n'
  printf 'Host machine : %s\n' "$HOST_MACHINE"
  printf 'Userspace    : %s\n' "$HOST_ARCH"
  printf 'Bits         : %s\n' "$HOST_BITS"
  printf 'Docker       : %s\n' "$DOCKER_ARCH"

  if [[ -n "${DOCKER_DEFAULT_PLATFORM:-}" ]]; then
    printf 'Platform     : %s\n' "$DOCKER_DEFAULT_PLATFORM"
  fi

  printf 'Database     : %s\n' "${DB_CONNECTION:-mysql}"
  printf '\n'
}

help() {
  printf '%s\n' \
    "$SCRIPT_NAME - Laravel Docker Manager" \
    '' \
    "Usage: $SCRIPT_NAME <command> [dev|prod|-d|-p]" \
    '' \
    'Commands:' \
    '  dev' \
    '  up' \
    '  down' \
    '  restart' \
    '  build' \
    '  logs' \
    '  ps' \
    '  health' \
    '  shell' \
    '  exec' \
    '  artisan' \
    '  composer' \
    '  npm' \
    '  vite' \
    '  migrate' \
    '  fresh' \
    '  deploy' \
    '  backup' \
    '  clean' \
    '  arch' \
    '  help'
}

backup_database() {
  local env="$1"

  mkdir -p backups

  local timestamp
  timestamp="$(date +%Y%m%d_%H%M%S)"

  if [[ "${USE_SQLITE:-0}" == "1" ]]; then

    log "Backing up SQLite database"

    compose "$env" exec -T app \
      cat /app/database/database.sqlite \
      > "backups/db_${env}_${timestamp}.sqlite"

    ok "SQLite backup created: backups/db_${env}_${timestamp}.sqlite"

    return
  fi

  #
  # MariaDB first.
  #
  if compose "$env" ps --services | grep -qx 'mariadb'; then

    log "Backing up MariaDB database"

    compose "$env" exec -T mariadb sh -c \
      'exec mariadb-dump \
        -uroot \
        -p"$MARIADB_ROOT_PASSWORD" \
        "$MARIADB_DATABASE"' \
      > "backups/db_${env}_${timestamp}.sql"

    ok "MariaDB backup created: backups/db_${env}_${timestamp}.sql"

    return
  fi

  #
  # Backward compatibility with old mysql service.
  #
  if compose "$env" ps --services | grep -qx 'mysql'; then

    log "Backing up MySQL database"

    compose "$env" exec -T mysql sh -c \
      'exec mysqldump \
        -uroot \
        -p"$MYSQL_ROOT_PASSWORD" \
        "$MYSQL_DATABASE"' \
      > "backups/db_${env}_${timestamp}.sql"

    ok "MySQL backup created: backups/db_${env}_${timestamp}.sql"

    return
  fi

  die "No supported database service found"
}

main() {
  if [[ $# -eq 0 \
     || "$1" == "help" \
     || "$1" == "-h" \
     || "$1" == "--help" ]]; then

    help
    return
  fi

  local cmd="$1"
  shift

  #
  # Architecture diagnostic.
  #
  if [[ "$cmd" == "arch" ]]; then
    show_arch
    return
  fi

  #
  # Production deployment.
  #
  if [[ "$cmd" == "deploy" ]]; then

    require_docker
    ensure_env "prod"
    choose_server "prod"

    compose prod pull
    compose prod build
    compose prod up -d --remove-orphans

    compose prod exec -T app \
      php artisan migrate --force

    compose prod exec -T app \
      php artisan config:cache

    compose prod exec -T app \
      php artisan route:cache

    compose prod exec -T app \
      php artisan view:cache

    compose prod exec -T app \
      php artisan event:cache

    if compose prod ps --services | grep -qx horizon; then
      compose prod exec -T horizon \
        php artisan horizon:terminate || true
    fi

    docker image prune -f >/dev/null

    ok "Deployed successfully"

    return
  fi

  local env

  env="$(resolve_env "${1:-dev}")"

  [[ $# -gt 0 ]] && shift

  ensure_env "$env"
  choose_server "$env"
  require_docker

  case "$cmd" in

    dev)

      [[ "$env" == "dev" ]] \
        || die "dev commands are only available in development"

      compose dev up -d --build

      compose dev exec -T app \
        composer install --no-interaction

      compose dev exec -T app \
        php artisan migrate --seed

      #
      # Vite may not be running on some ARM32 configurations.
      #
      if compose dev ps --services | grep -qx vite; then
        compose dev exec -T vite npm run build
      fi

      ok "Development environment started"
      ;;

    up)

      compose "$env" up -d --build

      if [[ "$env" == "dev" ]]; then
        compose dev exec -T app \
          composer install --no-interaction
      fi
      ;;

    down)

      compose "$env" down
      ;;

    restart)

      compose "$env" restart
      ;;

    build)

      compose "$env" build --no-cache
      ;;

    logs)

      compose "$env" logs -f --tail=100 "$@"
      ;;

    ps|health)

      compose "$env" ps
      ;;

    shell)

      compose "$env" exec "${1:-app}" sh
      ;;

    exec)

      compose "$env" exec "$@"
      ;;

    artisan)

      compose "$env" exec app \
        php artisan "$@"
      ;;

    composer)

      compose "$env" exec app \
        composer "$@"
      ;;

    npm)

      compose "$env" exec vite \
        npm "$@"
      ;;

    vite)

      [[ "$env" == "dev" ]] \
        || die "vite commands are only available in development"

      compose "$env" exec vite \
        npm exec -- vite "$@"
      ;;

    migrate)

      compose "$env" exec app \
        php artisan migrate "$@"
      ;;

    fresh)

      [[ "$env" == "prod" ]] \
        && die "Refusing to migrate:fresh in production"

      compose dev exec app \
        php artisan migrate:fresh --seed
      ;;

    backup)

      backup_database "$env"
      ;;

    clean)

      compose "$env" down -v --remove-orphans
      ;;

    *)

      die "Unknown command: $cmd"
      ;;
  esac
}

main "$@"