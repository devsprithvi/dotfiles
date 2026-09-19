// Package lsp implements pulipil's language server for pulipil.cue files.
//
// The server speaks the Language Server Protocol (LSP 3.17) over JSON-RPC on
// stdio and delivers the feature the whole project is built around: real-time,
// provider-aware package-name completion. As a user types a package `name`,
// the server resolves the governing provider from the surrounding config and
// asks that provider's completion source for live candidates.
//
// Two completion backends are supported behind one resolver:
//
//   - internet-backed sources (internal/remote) that query public registry
//     APIs directly (npm, crates.io, PyPI, Homebrew). Each registry has its
//     own request/response shape, isolated inside its Source. This is the
//     default and needs no local package manager installed.
//   - local command providers (internal/provider) that shell out to an
//     installed package manager's own `search`, used as a fallback.
//
// Layout of the package:
//
//	protocol.go  - JSON-RPC + LSP wire types
//	transport.go - Content-Length framed JSON-RPC connection
//	handler.go   - message loop, document store, completion context detection
//	server.go    - construction, the completion resolver, and Serve()
package lsp

import (
	"context"
	"fmt"
	"io"

	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/remote"
)

// Server is the language server. It holds a local provider registry (for
// fallback completion via installed package managers) and a registry of
// internet-backed completion sources (the default, real-time path).
type Server struct {
	reg     *provider.Registry
	remote  *remote.Registry
	out     io.Writer
	version string
}

// New returns a language server backed by the given provider registry. If a
// remote registry is not attached with WithRemote, the built-in internet
// sources are used by default so completion works out of the box.
func New(reg *provider.Registry, out io.Writer) *Server {
	return &Server{
		reg:     reg,
		remote:  remote.Default(nil),
		out:     out,
		version: "dev",
	}
}

// WithRemote overrides the internet-backed completion sources.
func (s *Server) WithRemote(r *remote.Registry) *Server {
	if r != nil {
		s.remote = r
	}
	return s
}

// WithVersion sets the version advertised to clients on initialize.
func (s *Server) WithVersion(v string) *Server {
	if v != "" {
		s.version = v
	}
	return s
}

// Roadmap describes shipped and planned capabilities, surfaced by
// `pulipil lsp --info`.
func Roadmap() []string {
	return []string{
		"[done] JSON-RPC 2.0 transport over stdio (initialize/shutdown lifecycle)",
		"[done] Document sync (full) of pulipil.cue buffers",
		"[done] Provider-aware completion resolved from the enclosing object",
		"[done] Real-time candidates from internet registries (npm/crates/pypi/brew)",
		"[done] Per-provider result shaping (name/version/description)",
		"[next] Schema-aware diagnostics using the embedded #Config definition",
		"[next] Hover + signature help for #Provider / #Package fields",
	}
}

// Serve runs the JSON-RPC message loop over the given streams until the client
// sends `exit` or the transport closes.
func (s *Server) Serve(ctx context.Context, r io.Reader, w io.Writer) error {
	c := newConn(r, w)
	return newHandler(s, c).run(ctx)
}

// Complete is the core resolver the LSP (and the `search` CLI) call. Given a
// provider/source name and a partial query, it returns completion candidates.
//
// Resolution order:
//  1. If a source name is given and an internet-backed source matches, query
//     it live. On a network/registry error, fall through to local.
//  2. If a local provider matches and is available, use its `search`.
//  3. If no name is given, try internet sources in the default order and
//     return the first non-empty result.
func (s *Server) Complete(ctx context.Context, providerName, query string) ([]provider.Candidate, error) {
	if providerName != "" {
		if src, ok := s.remote.Get(providerName); ok {
			if cands, err := src.Search(ctx, query); err == nil {
				return cands, nil
			}
			// remote failed; try a local provider of the same name below
		}
		if p, ok := s.reg.Get(providerName); ok {
			if !p.Available(ctx) {
				return nil, fmt.Errorf("provider %q is not available on this system", providerName)
			}
			return p.Search(ctx, query)
		}
		return nil, fmt.Errorf("unknown provider %q", providerName)
	}

	// No provider pinned: try internet sources in the default order.
	for _, name := range remote.DefaultOrder() {
		src, ok := s.remote.Get(name)
		if !ok {
			continue
		}
		if cands, err := src.Search(ctx, query); err == nil && len(cands) > 0 {
			return cands, nil
		}
	}
	return nil, nil
}
