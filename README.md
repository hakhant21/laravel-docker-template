# Laravel Docker Template

Production-ready Docker configuration for Laravel 13 with PHP-FPM, Nginx,
MySQL, Redis, Inertia, Vue, Wayfinder, Traefik, and GitHub Actions deployment.

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

Then configure `src/.env` for the Docker services, including `DB_HOST=mysql`
and `REDIS_HOST=redis`.

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
cp .env .env.production
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
