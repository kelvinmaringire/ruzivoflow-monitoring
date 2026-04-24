.PHONY: up down ps logs reload-prometheus

up:
	docker compose up -d

down:
	docker compose down

ps:
	docker compose ps

logs:
	docker compose logs -f --tail=200

reload-prometheus:
	curl -fsS -X POST http://127.0.0.1:9090/-/reload
