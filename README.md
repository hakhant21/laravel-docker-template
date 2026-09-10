# Laravel Docker Template

Production-ready Docker configuration for Laravel 13 with PHP-FPM, Nginx,
MySQL, Redis, Inertia, Vue, Wayfinder, Traefik, and GitHub Actions deployment.

## Project Structure

```text
.
├── .github/workflows/
│   ├── ci.yml
│   └── deploy.yml
├── backups/
├── docker/
│   ├── mysql/my.cnf
│   ├── nginx/
│   │   ├── default.conf
│   │   └── Dockerfile.prod
│   ├── octane/
│   │   ├── Dockerfile.fpm
│   │   ├── Dockerfile.octane
│   │   ├── Dockerfile.prod
│   │   ├── Dockerfile.prod.octane
│   │   ├── opcache.ini
│   │   └── php.ini
│   └── traefik/
│       ├── dynamic.yml
│       └── traefik.yml
├── src/                         # Laravel application
├── .dockerignore
├── .env.example                 # Docker Compose development defaults
├── .gitignore
├── app -> app.sh                 # Convenience symlink
├── app.sh                        # Docker management CLI
├── docker-compose.yml            # PHP-FPM + Nginx development stack
├── docker-compose.octane.yml     # Optional Octane development override
├── docker-compose.prod.yml       # PHP-FPM + Nginx production stack
├── docker-compose.prod.octane.yml
└── README.md
```

## Requirements

- Docker with Docker Compose
- Composer or the Laravel installer
- Bash

## Create the Laravel Application

The `src/` directory is the Laravel application directory. Create the
application there before starting Docker, using either Composer:

```bash
cd src
composer create-project laravel/laravel .
cd ..
```

Or the Laravel installer:

```bash
cd src
laravel new .
cd ..
```

Laravel creates `src/.env` automatically. Configure the environment files:

- Root `.env`: Docker Compose variables such as database credentials and
  `APP_SERVER`. Create it from `.env.example` if it does not exist.
- `src/.env`: Laravel runtime variables. Keep `DB_HOST=mysql` and
  `REDIS_HOST=redis` for Docker networking.

```bash
cp -n .env.example .env
```

Update `src/.env` with these Docker service settings:

```env
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret

REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=null
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
```

The root `.env.production` file is used only for production Compose variables.
Create it from `.env.example`, then set strong passwords, `APP_DOMAIN`, and
`GITHUB_REPOSITORY`. Update the production Laravel values in `src/.env`.

## Development

Start the development services:

```bash
./app.sh up dev
```

On the first run, `app.sh` asks which application server to use:

1. PHP-FPM + Nginx (default)
2. Laravel Octane

Your choice is saved as `APP_SERVER` in `.env`, so later commands reuse it.
To choose again, remove the `APP_SERVER` line from `.env` and run an `app.sh`
command.

Bootstrap a new Laravel installation:

```bash
./app.sh artisan dev key:generate
./app.sh artisan dev migrate
./app.sh artisan dev storage:link
./app.sh npm dev install
```

Services are available at:

- Application: <http://localhost:8000>
- Vite: <http://localhost:5173>
- Nginx is exposed on port `8000` and forwards PHP requests to PHP-FPM.
- Mailpit: <http://localhost:8025>
- MySQL: `localhost:3306`
- Redis: `localhost:6379`

View available commands with:

```bash
./app.sh help
```

The `app` symlink points to `app.sh`, so you can also run:

```bash
./app help
```

For a system-wide command, create a symlink to the script:

```bash
sudo ln -sf "$PWD/app.sh" /usr/local/bin/app
```

## Production

Copy and configure the production environment:

```bash
cp .env.example .env.production
```

Set `DB_PASSWORD`, `REDIS_PASSWORD`, `GITHUB_REPOSITORY`, and `APP_DOMAIN` in
`.env.production`. The first production command asks for the Let's Encrypt
email address and saves it as `ACME_EMAIL`.

Deploy manually with:

```bash
./app.sh deploy
```

The GitHub Actions workflow builds and pushes the production image to GHCR,
then deploys it to the configured server after a push to `main`.

Required GitHub secrets:

- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
- `GITHUB_TOKEN` is provided automatically by GitHub Actions

## Useful Commands

### Development Commands

```bash
# Start, stop, rebuild, or restart services
./app.sh up dev
./app.sh down dev
./app.sh restart dev
./app.sh build dev

# Inspect services and follow logs
./app.sh ps dev
./app.sh health dev
./app.sh logs dev
./app.sh logs dev app

# Open a shell or run commands in containers
./app.sh shell dev
./app.sh shell dev mysql
./app.sh exec dev app php artisan about

# Run Laravel, Composer, and npm commands
./app.sh artisan dev migrate
./app.sh artisan dev tinker
./app.sh composer dev install
./app.sh npm dev run build

# Reset the development database, back it up, or remove all volumes
./app.sh fresh dev
./app.sh backup dev
./app.sh clean dev
```

### Production Commands

```bash
./app.sh deploy
./app.sh up prod
./app.sh ps prod
./app.sh logs prod horizon
./app.sh shell prod queue
./app.sh artisan prod queue:restart
./app.sh backup prod
./app.sh down prod
```

Do not commit `.env.production` or database backups.
