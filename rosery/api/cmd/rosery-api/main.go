package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"rosery/api/internal/attest"
	"rosery/api/internal/config"
	"rosery/api/internal/httpapi"
	"rosery/api/internal/quran"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("API stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	a, err := attest.New(attest.Config{AppID: cfg.AppleAppID, Environment: cfg.AttestEnv, StorePath: cfg.StorePath})
	if err != nil {
		return err
	}
	defer func() {
		if err := a.Close(); err != nil {
			logger.Error("device store close failed")
		}
	}()
	content, err := quran.New(quran.Config{ClientID: cfg.QFClientID, ClientSecret: cfg.QFClientSecret, Environment: cfg.QFEnvironment})
	if err != nil {
		return err
	}
	server := httpapi.New(cfg, a, content, logger).HTTPServer()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	done := make(chan error, 1)
	go func() { done <- server.ListenAndServe() }()
	logger.Info("API starting", "address", cfg.Address, "environment", cfg.Environment, "quran_environment", cfg.QFEnvironment)
	select {
	case err := <-done:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			_ = server.Close()
			return err
		}
		return nil
	}
}
