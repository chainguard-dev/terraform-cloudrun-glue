/*
Copyright 2023 Chainguard, Inc.
SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"context"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"

	cloudevents "github.com/cloudevents/sdk-go/v2"
	"github.com/sethvargo/go-envconfig"
	"gocloud.dev/blob"

	"github.com/chainguard-dev/clog"
	_ "github.com/chainguard-dev/clog/gcp/init"
	"github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics"
	mce "github.com/chainguard-dev/terraform-infra-common/pkg/httpmetrics/cloudevents"
	"github.com/chainguard-dev/terraform-infra-common/pkg/profiler"

	// Add gcsblob support that we need to support gs:// prefixes
	_ "gocloud.dev/blob/gcsblob"
)

var env = envconfig.MustProcess(context.Background(), &struct {
	Port          int           `env:"PORT, default=8080"`
	FlushInterval time.Duration `env:"FLUSH_INTERVAL, default=3m"`
	Bucket        string        `env:"BUCKET, required"`
}{})

func main() {
	profiler.SetupProfiler()

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	go httpmetrics.ServeMetrics()
	defer httpmetrics.SetupTracer(ctx)()

	c, err := mce.NewClientHTTP("ce-recorder", cloudevents.WithPort(env.Port))
	if err != nil {
		clog.Fatalf("failed to create event client, %v", err)
	}

	bucket, err := blob.OpenBucket(ctx, env.Bucket)
	if err != nil {
		clog.Fatalf("failed to open bucket, %v", err)
	}
	defer bucket.Close()

	var m sync.Mutex
	writers := make(map[string]*blob.Writer, 10)

	// Periodically flush the writers to commit the data to the bucket.
	go func() {
		done := false
		for {
			writersToDrain := func() map[string]*blob.Writer {
				m.Lock()
				defer m.Unlock()
				// Swap the writers map so we can safely iterate and close the writers.
				writersToDrain := writers
				writers = make(map[string]*blob.Writer, 10)
				return writersToDrain
			}()

			for t, w := range writersToDrain {
				clog.Infof("Flushing writer[%s]", t)
				if err := w.Close(); err != nil {
					clog.Errorf("failed to close writer[%s]: %v", t, err)
				}
			}

			if done {
				clog.InfoContextf(ctx, "Exiting flush loop")
				return
			}
			select {
			case <-time.After(env.FlushInterval):
			case <-ctx.Done():
				clog.InfoContext(ctx, "Flushing one more time")
				done = true
			}
		}
	}()

	// Listen for events and as they come in write them to the appropriate
	// writer based on event type.
	if err := c.StartReceiver(ctx, func(_ context.Context, event cloudevents.Event) error {
		writer, err := func() (*blob.Writer, error) {
			m.Lock()
			defer m.Unlock()

			w, ok := writers[event.Type()]
			if !ok {
				w, err = bucket.NewWriter(ctx, filepath.Join(event.Type(), strconv.FormatInt(time.Now().UnixNano(), 10)), nil)
				if err != nil {
					clog.Errorf("failed to create writer: %v", err)
					return nil, err
				}
			}
			writers[event.Type()] = w
			return w, nil
		}()
		if err != nil {
			clog.Errorf("failed to create writer: %v", err)
			return err
		}

		// Write the event data as a line to the writer.
		line := string(event.Data())
		if _, err := writer.Write([]byte(line + "\n")); err != nil {
			clog.Errorf("failed to write event data: %v", err)
			return err
		}

		return nil
	}); err != nil {
		clog.Fatalf("failed to start event receiver, %v", err)
	}
}
