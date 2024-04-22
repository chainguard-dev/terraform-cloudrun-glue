package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"time"

	"cloud.google.com/go/bigquery"
	"github.com/chainguard-dev/clog"
	cloudevents "github.com/cloudevents/sdk-go/v2"
	cehttp "github.com/cloudevents/sdk-go/v2/protocol/http"
	"github.com/kelseyhightower/envconfig"
	"google.golang.org/api/iterator"
)

const (
	retryDelay = 10 * time.Millisecond
	maxRetry   = 3
)

type envConfig struct {
	Host string `envconfig:"HOST" default:"http://0.0.0.0" required:"true"`
	Port int    `envconfig:"PORT" default:"8080" required:"true"`

	EventType   string `envconfig:"EVENT_TYPE" default:"dev.chainguard.not_specified.not_specified" required:"true"`
	EventSource string `envconfig:"EVENT_SOURCE" default:"github.com" required:"true"`

	// Project is the GCP project where the dataset lives
	Project string `envconfig:"PROJECT" required:"true"`

	// QueryWindow is the window to look for release failures
	Query string `envconfig:"QUERY" required:"true"`
}

func Publish(ctx context.Context, env envConfig, event cloudevents.Event) error {
	log := clog.FromContext(ctx)

	// TODO: Add idtoken back?
	ceclient, err := cloudevents.NewClientHTTP(
		cloudevents.WithTarget(fmt.Sprintf("%s:%d", env.Host, env.Port)),
		cehttp.WithClient(http.Client{}))
	if err != nil {
		log.Fatalf("failed to create cloudevents client: %v", err)
	}

	rctx := cloudevents.ContextWithRetriesExponentialBackoff(context.WithoutCancel(ctx), retryDelay, maxRetry)
	ceresult := ceclient.Send(rctx, event)
	if cloudevents.IsUndelivered(ceresult) || cloudevents.IsNACK(ceresult) {
		log.Errorf("Failed to deliver event: %v", ceresult)
	}

	return nil
}

func main() {
	var env envConfig
	if err := envconfig.Process("", &env); err != nil {
		clog.Fatalf("failed to process env var: %s", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	log := clog.FromContext(ctx)

	// TODO: Cache older queries, presumably a use case is replaying the same
	// data over and over so we can cache it so we avoid hitting bq every time

	// BigQuery client
	client, err := bigquery.NewClient(ctx, env.Project)
	if err != nil {
		log.Fatalf("failed to create bigquery client: %v", err)
	}
	defer client.Close()

	q := client.Query(env.Query)
	it, err := q.Read(ctx)
	if err != nil {
		log.Error(env.Query)
		log.Fatalf("failed to run thresholdQuery, %v", err)
	}

	// Iterate through each row in the returned query and handle every module
	// that is above the failure threshold.
	for {
		var row map[string]bigquery.Value
		err = it.Next(&row)
		if err == iterator.Done {
			break
		}
		if err != nil {
			log.Errorf("failed to read row, %v", err)
		}

		log.Infof("%+v\n", row)

		body, err := json.Marshal(row)
		if err != nil {
			log.Fatalf("marshaling row: %v", err)
		}
		log.Info(string(body))

		// TODO: Extract event type
		log = log.With("event-type", env.EventType)
		log.Debugf("forwarding event: %s", env.EventType)

		event := cloudevents.NewEvent()
		event.SetType(env.EventType)
		event.SetSource(env.EventSource)
		if err := event.SetData(cloudevents.ApplicationJSON, body); err != nil {
			log.Fatalf("failed to set data: %v", err)
		}

		// TODO: Time based publishing if we care about replaying using the
		// timestamps in the dataset
		Publish(ctx, env, event)
	}
}
