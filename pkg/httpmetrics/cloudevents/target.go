/*
Copyright 2023 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package cloudevents

import (
	"context"
	"log"
	"net/http"
	"strings"

	metrics "github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
	cehttp "github.com/cloudevents/sdk-go/v2/protocol/http"
)

// WithTarget wraps cloudevents.WithTarget to authenticate requests with an
// identity token when the target is an HTTPS URL.
func WithTarget(ctx context.Context, url string) []cehttp.Option {
	opts := make([]cehttp.Option, 0, 2)

	if strings.HasPrefix(url, "https://") {
		idc, err := metrics.NewIDTokenClient(ctx, url)
		if err != nil {
			log.Panicf("failed to create idtoken client: %v", err)
		}
		// If we don't specify a client, NewClientHTTP will use http.DefaultClient
		// and may clobber its Transport. To avoid so, we pass a client with the
		// the metrics transport instead.
		metricsClient := http.Client{
			Transport: metrics.WrapTransport(idc.Transport),
		}
		opts = append(opts, cehttp.WithClient(metricsClient))
	}

	opts = append(opts, cehttp.WithTarget(url))
	return opts
}
