package runtime

import (
	"context"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"io"
	"net/http"
	"strings"
	"testing"
)

type auditTransport struct{ request *http.Request }

func (t *auditTransport) Do(r *http.Request) (*http.Response, error) {
	t.request = r
	return &http.Response{StatusCode: 200, Header: http.Header{}, Body: io.NopCloser(strings.NewReader("{}")), Request: r}, nil
}
func TestRemovedTelemetryPolicy(t *testing.T) {
	transport := &auditTransport{}
	pipeline := NewPipeline("audit", "v1.0.0", PipelineOptions{}, &policy.ClientOptions{
		Transport: transport, Telemetry: policy.TelemetryOptions{ApplicationID: "must-not-be-reported", Disabled: false},
	})
	req, err := NewRequest(context.Background(), http.MethodGet, "https://example.invalid/resource")
	if err != nil {
		t.Fatal(err)
	}
	req.Raw().Header.Set("Authorization", "Bearer test-only")
	if _, err = pipeline.Do(req); err != nil {
		t.Fatal(err)
	}
	if transport.request == nil {
		t.Fatal("request was not forwarded")
	}
	if got := transport.request.Header.Get("User-Agent"); got != "" {
		t.Fatalf("telemetry header: %q", got)
	}
	if got := transport.request.Header.Get("Authorization"); got != "Bearer test-only" {
		t.Fatal("authentication header lost")
	}
}
