package corehandlers

import (
	"github.com/aws/aws-sdk-go/aws/request"
	"net/http"
	"testing"
)

func TestRemovedSDKUsageReporting(t *testing.T) {
	t.Setenv("AWS_EXECUTION_ENV", "must-not-be-reported")
	raw, _ := http.NewRequest(http.MethodGet, "https://example.invalid/resource", nil)
	raw.Header.Set("Authorization", "signed-test-request")
	r := &request.Request{HTTPRequest: raw}
	SDKVersionUserAgentHandler.Fn(r)
	AddHostExecEnvUserAgentHander.Fn(r)
	AddAwsInternal.Fn(r)
	request.MakeAddToUserAgentHandler("app", "1", "machine")(r)
	request.MakeAddToUserAgentFreeFormHandler("feature")(r)
	request.AddToUserAgent(r, "report")
	if raw.Header.Get("User-Agent") != "" {
		t.Fatal("SDK reporting header present")
	}
	if raw.Header.Get("Authorization") != "signed-test-request" {
		t.Fatal("authentication changed")
	}
}
