## Top-level convenience targets. Each subproject has its own Makefile
## or scripts; this just hops into them for "do everything" runs.

.PHONY: all backend mac typecheck test clean

all: typecheck test

backend:
	cd backend && npm install --silent

mac:
	cd mac && make project

typecheck:
	cd backend && npx tsc
	cd mac && swift build

test:
	cd backend && npx vitest run
	cd mac && swift test

clean:
	cd backend && rm -rf node_modules dist
	cd mac && make clean
