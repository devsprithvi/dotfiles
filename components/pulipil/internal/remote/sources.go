package remote

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"

	"github.com/devsprithvi/pulipil/internal/provider"
)

// DefaultOrder is the preference used when the editor cannot infer a provider
// from the document. npm and crates.io offer true prefix search, so they make
// the best "no context" defaults.
func DefaultOrder() []string {
	return []string{"npm", "crates", "pypi", "brew"}
}

// Default returns a registry populated with pulipil's built-in internet-backed
// sources. Pass nil to use a client with a sane default timeout, or inject a
// custom client (tests use this to point at an httptest server).
func Default(client *http.Client) *Registry {
	ua := "pulipil-lsp (+https://github.com/devsprithvi/pulipil)"
	reg := NewRegistry()
	reg.Register(NPM(client, ua, ""))
	reg.Register(Crates(client, ua, ""))
	reg.Register(PyPI(client, ua, ""))
	reg.Register(Brew(client, ua, ""))
	return reg
}

// ---------------------------------------------------------------------------
// npm — registry search API.
// GET https://registry.npmjs.org/-/v1/search?text=<q>&size=25
// Shape: {"objects":[{"package":{"name","version","description"}}]}
// ---------------------------------------------------------------------------

// NPM returns the npm registry source. baseURL overrides the API root (tests).
func NPM(client *http.Client, userAgent, baseURL string) Source {
	if baseURL == "" {
		baseURL = "https://registry.npmjs.org"
	}
	return &httpSource{
		name:      "npm",
		baseURL:   strings.TrimRight(baseURL, "/"),
		client:    clientOr(client),
		userAgent: userAgent,
		build: func(base, query string) (string, error) {
			qs := encodeQuery(map[string]string{"text": query, "size": "25"})
			return base + "/-/v1/search?" + qs, nil
		},
		shape: shapeNPM,
	}
}

func shapeNPM(body []byte) ([]provider.Candidate, error) {
	var payload struct {
		Objects []struct {
			Package struct {
				Name        string `json:"name"`
				Version     string `json:"version"`
				Description string `json:"description"`
			} `json:"package"`
		} `json:"objects"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	out := make([]provider.Candidate, 0, len(payload.Objects))
	for _, o := range payload.Objects {
		out = append(out, provider.Candidate{
			Name:        o.Package.Name,
			Version:     o.Package.Version,
			Description: o.Package.Description,
		})
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// crates.io — search API. Requires a descriptive User-Agent.
// GET https://crates.io/api/v1/crates?q=<q>&per_page=25
// Shape: {"crates":[{"name","max_version","description"}]}
// ---------------------------------------------------------------------------

// Crates returns the crates.io source.
func Crates(client *http.Client, userAgent, baseURL string) Source {
	if baseURL == "" {
		baseURL = "https://crates.io"
	}
	return &httpSource{
		name:      "crates",
		baseURL:   strings.TrimRight(baseURL, "/"),
		client:    clientOr(client),
		userAgent: userAgent,
		build: func(base, query string) (string, error) {
			qs := encodeQuery(map[string]string{"q": query, "per_page": "25"})
			return base + "/api/v1/crates?" + qs, nil
		},
		shape: shapeCrates,
	}
}

func shapeCrates(body []byte) ([]provider.Candidate, error) {
	var payload struct {
		Crates []struct {
			Name        string `json:"name"`
			MaxVersion  string `json:"max_version"`
			Description string `json:"description"`
		} `json:"crates"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	out := make([]provider.Candidate, 0, len(payload.Crates))
	for _, c := range payload.Crates {
		out = append(out, provider.Candidate{
			Name:        c.Name,
			Version:     c.MaxVersion,
			Description: strings.TrimSpace(c.Description),
		})
	}
	return out, nil
}

// ---------------------------------------------------------------------------
// PyPI — no general search API remains, so this is an exact-name lookup that
// still gives real-time, authoritative completion once a full name is typed.
// GET https://pypi.org/pypi/<name>/json
// Shape: {"info":{"name","version","summary"}}
// ---------------------------------------------------------------------------

// PyPI returns the PyPI source (exact-name lookup).
func PyPI(client *http.Client, userAgent, baseURL string) Source {
	if baseURL == "" {
		baseURL = "https://pypi.org"
	}
	return &httpSource{
		name:      "pypi",
		baseURL:   strings.TrimRight(baseURL, "/"),
		client:    clientOr(client),
		userAgent: userAgent,
		build: func(base, query string) (string, error) {
			return base + "/pypi/" + url.PathEscape(query) + "/json", nil
		},
		shape: shapePyPI,
	}
}

func shapePyPI(body []byte) ([]provider.Candidate, error) {
	var payload struct {
		Info struct {
			Name    string `json:"name"`
			Version string `json:"version"`
			Summary string `json:"summary"`
		} `json:"info"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	if payload.Info.Name == "" {
		return nil, nil
	}
	return []provider.Candidate{{
		Name:        payload.Info.Name,
		Version:     payload.Info.Version,
		Description: payload.Info.Summary,
	}}, nil
}

// ---------------------------------------------------------------------------
// Homebrew — formulae.brew.sh exposes a per-formula JSON document. Like PyPI
// this is an exact-name lookup with yet another distinct shape (versions is a
// nested object, description is `desc`).
// GET https://formulae.brew.sh/api/formula/<name>.json
// Shape: {"name","desc","versions":{"stable"}}
// ---------------------------------------------------------------------------

// Brew returns the Homebrew formulae source (exact-name lookup).
func Brew(client *http.Client, userAgent, baseURL string) Source {
	if baseURL == "" {
		baseURL = "https://formulae.brew.sh"
	}
	return &httpSource{
		name:      "brew",
		baseURL:   strings.TrimRight(baseURL, "/"),
		client:    clientOr(client),
		userAgent: userAgent,
		build: func(base, query string) (string, error) {
			return base + "/api/formula/" + url.PathEscape(query) + ".json", nil
		},
		shape: shapeBrew,
	}
}

func shapeBrew(body []byte) ([]provider.Candidate, error) {
	var payload struct {
		Name     string `json:"name"`
		Desc     string `json:"desc"`
		Versions struct {
			Stable string `json:"stable"`
		} `json:"versions"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	if payload.Name == "" {
		return nil, nil
	}
	return []provider.Candidate{{
		Name:        payload.Name,
		Version:     payload.Versions.Stable,
		Description: payload.Desc,
	}}, nil
}
