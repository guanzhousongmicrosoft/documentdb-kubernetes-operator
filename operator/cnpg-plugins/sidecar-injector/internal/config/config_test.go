// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

package config

import (
	"testing"

	"github.com/cloudnative-pg/cnpg-i-machinery/pkg/pluginhelper/common"
)

func TestApplyDefaults(t *testing.T) {
	t.Run("sets default gateway image when empty", func(t *testing.T) {
		config := &Configuration{}
		config.applyDefaults()
		expected := "ghcr.io/documentdb/documentdb-kubernetes-operator/gateway:0.110.0"
		if config.GatewayImage != expected {
			t.Errorf("expected %q, got %q", expected, config.GatewayImage)
		}
	})

	t.Run("preserves explicit gateway image", func(t *testing.T) {
		config := &Configuration{GatewayImage: "custom:latest"}
		config.applyDefaults()
		if config.GatewayImage != "custom:latest" {
			t.Errorf("expected custom:latest, got %q", config.GatewayImage)
		}
	})
}

func TestFromParameters(t *testing.T) {
	t.Run("parses gateway image from parameters", func(t *testing.T) {
		helper := &common.Plugin{Parameters: map[string]string{
			"gatewayImage": "my-gateway:v1",
		}}
		config, errs := FromParameters(helper)
		if len(errs) != 0 {
			t.Fatalf("unexpected validation errors: %v", errs)
		}
		if config.GatewayImage != "my-gateway:v1" {
			t.Errorf("GatewayImage = %q, want %q", config.GatewayImage, "my-gateway:v1")
		}
	})

	t.Run("uses default when gateway image not set", func(t *testing.T) {
		helper := &common.Plugin{Parameters: map[string]string{}}
		config, errs := FromParameters(helper)
		if len(errs) != 0 {
			t.Fatalf("unexpected validation errors: %v", errs)
		}
		expected := "ghcr.io/documentdb/documentdb-kubernetes-operator/gateway:0.110.0"
		if config.GatewayImage != expected {
			t.Errorf("GatewayImage = %q, want %q", config.GatewayImage, expected)
		}
	})
}

func TestToParametersRoundTrip(t *testing.T) {
	original := &Configuration{
		GatewayImage: "my-image:latest",
	}
	original.applyDefaults()

	params, err := original.ToParameters()
	if err != nil {
		t.Fatalf("ToParameters() error: %v", err)
	}

	// Round-trip back through FromParameters
	helper := &common.Plugin{Parameters: params}
	restored, errs := FromParameters(helper)
	if len(errs) != 0 {
		t.Fatalf("unexpected validation errors: %v", errs)
	}
	if restored.GatewayImage != original.GatewayImage {
		t.Errorf("round-trip gateway image = %q, want %q", restored.GatewayImage, original.GatewayImage)
	}
}
