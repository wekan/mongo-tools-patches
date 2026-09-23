package comm

import (
	"net/http"
	"testing"
)

func TestRemovedClientFingerprint(t *testing.T) {
	h := http.Header{"Authorization": []string{"Bearer test-only"}}
	addStdHeaders(h)
	for _, key := range []string{"x-client-sku", "x-client-os", "x-client-cpu", "x-client-ver"} {
		if h.Get(key) != "" {
			t.Fatalf("fingerprint header %s present", key)
		}
	}
	if h.Get("Authorization") != "Bearer test-only" {
		t.Fatal("authentication changed")
	}
	if h.Get("client-request-id") == "" {
		t.Fatal("request correlation removed")
	}
}
