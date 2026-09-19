package remote

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

// newTestServer returns an httptest server routing the known registry paths to
// canned, real-shaped payloads so each shaper is exercised without network.
func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()

	// npm search
	mux.HandleFunc("/-/v1/search", func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("text"); got != "left" {
			t.Errorf("npm text = %q, want %q", got, "left")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"objects":[
			{"package":{"name":"left-pad","version":"1.3.0","description":"String left pad"}},
			{"package":{"name":"leftpad","version":"0.0.1","description":"another"}}
		]}`))
	})

	// crates.io search
	mux.HandleFunc("/api/v1/crates", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("crates.io request missing User-Agent")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"crates":[
			{"name":"serde","max_version":"1.0.203","description":"A serialization framework"}
		]}`))
	})

	// PyPI exact lookup
	mux.HandleFunc("/pypi/requests/json", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"info":{"name":"requests","version":"2.32.3","summary":"HTTP for Humans."}}`))
	})

	// Homebrew exact lookup
	mux.HandleFunc("/api/formula/wget.json", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"name":"wget","desc":"Internet file retriever","versions":{"stable":"1.24.5"}}`))
	})

	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestSourcesShapeResults(t *testing.T) {
	srv := newTestServer(t)
	ctx := context.Background()
	ua := "pulipil-test"

	cases := []struct {
		name     string
		source   Source
		query    string
		wantName string
		wantVer  string
	}{
		{"npm", NPM(srv.Client(), ua, srv.URL), "left", "left-pad", "1.3.0"},
		{"crates", Crates(srv.Client(), ua, srv.URL), "serde", "serde", "1.0.203"},
		{"pypi", PyPI(srv.Client(), ua, srv.URL), "requests", "requests", "2.32.3"},
		{"brew", Brew(srv.Client(), ua, srv.URL), "wget", "wget", "1.24.5"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.source.Search(ctx, tc.query)
			if err != nil {
				t.Fatalf("Search: %v", err)
			}
			if len(got) == 0 {
				t.Fatal("no candidates returned")
			}
			if got[0].Name != tc.wantName {
				t.Errorf("Name = %q, want %q", got[0].Name, tc.wantName)
			}
			if got[0].Version != tc.wantVer {
				t.Errorf("Version = %q, want %q", got[0].Version, tc.wantVer)
			}
		})
	}
}

func TestEmptyQueryReturnsNothing(t *testing.T) {
	src := NPM(http.DefaultClient, "ua", "http://example.invalid")
	got, err := src.Search(context.Background(), "   ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != nil {
		t.Fatalf("want nil candidates for empty query, got %v", got)
	}
}

func TestNotFoundIsNotAnError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "nope", http.StatusNotFound)
	}))
	t.Cleanup(srv.Close)

	src := PyPI(srv.Client(), "ua", srv.URL)
	got, err := src.Search(context.Background(), "does-not-exist")
	if err != nil {
		t.Fatalf("404 should not be an error, got %v", err)
	}
	if got != nil {
		t.Fatalf("want nil candidates on 404, got %v", got)
	}
}

func TestRegistryDefaultOrder(t *testing.T) {
	reg := Default(nil)
	for _, name := range DefaultOrder() {
		if !reg.Has(name) {
			t.Errorf("default registry missing source %q", name)
		}
	}
}
