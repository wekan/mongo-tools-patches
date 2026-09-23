package middleware

import (
	"context"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/smithy-go/middleware"
	smithyhttp "github.com/aws/smithy-go/transport/http"
	"net/http"
	"reflect"
	"testing"
)

func TestRemovedSDKUsageReporting(t *testing.T) {
	t.Setenv("AWS_EXECUTION_ENV", "must-not-be-reported")
	u := NewRequestUserAgent()
	u.AddUserAgentKey("application")
	u.AddUserAgentKeyValue("feature", "enabled")
	u.AddSDKAgentKey(OperatingSystemMetadata, "os")
	u.AddSDKAgentKeyValue(AdditionalMetadata, "machine", "identity")
	u.AddCredentialsSource(aws.CredentialSourceIMDS)
	u.AddUserAgentFeature(UserAgentFeature("A"))
	if reflect.ValueOf(*u).NumField() != 0 {
		t.Fatal("reporting state retained")
	}
	raw, _ := http.NewRequest(http.MethodGet, "https://example.invalid/resource", nil)
	raw.Header.Set("Authorization", "signed-test-request")
	nextCalled := false
	next := middleware.BuildHandlerFunc(func(ctx context.Context, in middleware.BuildInput) (middleware.BuildOutput, middleware.Metadata, error) {
		nextCalled = true
		r := in.Request.(*smithyhttp.Request)
		if r.Header.Get("User-Agent") != "" || r.Header.Get("X-Amz-User-Agent") != "" {
			t.Fatal("SDK reporting headers present")
		}
		if r.Header.Get("Authorization") != "signed-test-request" {
			t.Fatal("authentication changed")
		}
		return middleware.BuildOutput{}, middleware.Metadata{}, nil
	})
	_, _, err := u.HandleBuild(context.Background(), middleware.BuildInput{Request: &smithyhttp.Request{Request: raw}}, next)
	if err != nil || !nextCalled {
		t.Fatalf("request not forwarded: %v", err)
	}
}
