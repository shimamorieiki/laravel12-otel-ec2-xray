.PHONY: help up down build restart logs shell composer artisan migrate fresh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

up: ## Start all containers
	docker-compose up -d

down: ## Stop all containers
	docker-compose down

build: ## Build containers
	docker-compose build

restart: ## Restart all containers
	docker-compose restart

logs: ## Show logs
	docker-compose logs -f

shell: ## Access app container shell
	docker-compose exec app bash

composer: ## Run composer install
	docker-compose exec app composer install

artisan: ## Run artisan commands (usage: make artisan cmd="migrate")
	docker-compose exec app php artisan $(cmd)

migrate: ## Run database migrations
	docker-compose exec app php artisan migrate

fresh: ## Fresh migration with seeders
	docker-compose exec app php artisan migrate:fresh --seed

setup: ## Initial setup
	cp .env.docker .env
	make build
	make up
	make composer
	make migrate