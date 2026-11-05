.PHONY: run build test check lint fmt vuln
run:
	go run ./cmd/rosery-api
build:
	go build -trimpath -o bin/rosery-api ./cmd/rosery-api
test:
	go test -race ./...
check: test
	go vet ./...
lint:
	golangci-lint run ./...
fmt:
	gofmt -w cmd internal
vuln:
	go run golang.org/x/vuln/cmd/govulncheck@latest ./...
