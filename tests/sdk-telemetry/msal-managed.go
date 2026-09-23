package managedidentity

import (
	"context"
	"testing"
)

func TestRemovedClientFingerprint(t *testing.T) {
	req, err := createIMDSAuthRequest(context.Background(), SystemAssigned(), "https://example.invalid")
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"x-client-SKU", "x-client-Ver"} {
		if req.Header.Get(key) != "" {
			t.Fatalf("fingerprint header %s present", key)
		}
	}
	if req.Header.Get("Metadata") != "true" {
		t.Fatal("required metadata header lost")
	}
	if req.URL.Query().Get("resource") != "https://example.invalid" {
		t.Fatal("token resource lost")
	}
}
