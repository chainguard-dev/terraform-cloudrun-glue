/*
Copyright 2023 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package kms

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"

	kms "cloud.google.com/go/kms/apiv1"
	"cloud.google.com/go/kms/apiv1/kmspb"
	"github.com/golang-jwt/jwt/v4"
)

type SigningMethodGCP struct {
	ctx    context.Context
	client *kms.KeyManagementClient
}

func (s *SigningMethodGCP) Verify(string, string, interface{}) error {
	return errors.New("not implemented")
}

func (s *SigningMethodGCP) Sign(signingString string, ikey interface{}) (string, error) {
	ctx := s.ctx

	key, ok := ikey.(string)
	if !ok {
		return "", fmt.Errorf("invalid key reference type: %T", ikey)
	}
	req := &kmspb.AsymmetricSignRequest{
		Name: key,
		Data: []byte(signingString),
	}
	resp, err := s.client.AsymmetricSign(ctx, req)
	if err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(resp.Signature), nil
}

func (s *SigningMethodGCP) Alg() string {
	return "RS256"
}

type GCPSigner struct {
	ctx    context.Context
	client *kms.KeyManagementClient
	key    string
}

func NewGCP(ctx context.Context, client *kms.KeyManagementClient, key string) (*GCPSigner, error) {
	return &GCPSigner{
		ctx:    ctx,
		client: client,
		key:    key,
	}, nil
}

// Sign signs the JWT claims with the RSA key.
func (s *GCPSigner) Sign(claims jwt.Claims) (string, error) {
	method := &SigningMethodGCP{
		ctx:    s.ctx,
		client: s.client,
	}
	return jwt.NewWithClaims(method, claims).SignedString(s.key)
}
