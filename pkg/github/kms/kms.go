/*
Copyright 2023 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package kms

import (
	"context"
	"fmt"
	"os"
	"strings"

	kms "cloud.google.com/go/kms/apiv1"
	"github.com/bradleyfalzon/ghinstallation/v2"
	"github.com/golang-jwt/jwt/v4"
)

// NewSigner creates a new signer based on a key url.
// Supported URL schemes:
// - file://<path>: creates a signer from a PEM encoded RSA private key from a file.
// - gcpkms://<key>: creates a remote signer for a GCP KMS key.
func NewSigner(ctx context.Context, url string) (ghinstallation.Signer, error) {
	t := strings.SplitN(url, "://", 2)
	if len(t) < 2 {
		return nil, fmt.Errorf("invalid key format: %s", url)
	}

	switch t[0] {
	case "file":
		pk, err := os.ReadFile(t[1])
		if err != nil {
			return nil, fmt.Errorf("could not open file: %w", err)
		}
		rsa, err := jwt.ParseRSAPrivateKeyFromPEM(pk)
		if err != nil {
			return nil, fmt.Errorf("could not parse private key: %w", err)
		}
		return ghinstallation.NewRSASigner(jwt.SigningMethodRS256, rsa), nil

	case "gcpkms":
		client, err := kms.NewKeyManagementClient(ctx)
		if err != nil {
			return nil, fmt.Errorf("could not create kms client: %w", err)
		}
		return NewGCP(ctx, client, t[1])
	}
	return nil, fmt.Errorf("unknown key type: %s", t[0])
}
