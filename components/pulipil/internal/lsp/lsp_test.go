package lsp

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/devsprithvi/pulipil/internal/provider"
	"github.com/devsprithvi/pulipil/internal/remote"
)

func TestAnalyzeDetectsNameFieldAndProvider(t *testing.T) {
	tests := []struct {
		name         string
		text         string
		line, char   int
		wantOK       bool
		wantQuery    string
		wantProvider string
	}{
		{
			name:         "inline object with provider",
			text:         `packages: [{name: "ser", provider: "crates"}]`,
			line:         0,
			char:         len(`packages: [{name: "ser`),
			wantOK:       true,
			wantQuery:    "ser",
			wantProvider: "crates",
		},
		{
			name:         "multiline object, provider on later line",
			text:         "packages: [\n\t{\n\t\tname: \"left\"\n\t\tprovider: \"npm\"\n\t},\n]",
			line:         2,
			char:         len("\t\tname: \"left"),
			wantOK:       true,
			wantQuery:    "left",
			wantProvider: "npm",
		},
		{
			name:         "no provider pin falls back to auto",
			text:         `packages: [{name: "wg"}]`,
			line:         0,
			char:         len(`packages: [{name: "wg`),
			wantOK:       true,
			wantQuery:    "wg",
			wantProvider: "",
		},
		{
			name:   "cursor not on a name field",
			text:   `packages: [{name: "x", provider: "npm"}]`,
			line:   0,
			char:   len(`packages: [{name: "x", provider: "np`),
			wantOK: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cc, ok := analyze(tc.text, position{Line: tc.line, Character: tc.char})
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v (cc=%+v)", ok, tc.wantOK, cc)
			}
			if !ok {
				return
			}
			if cc.query != tc.wantQuery {
				t.Errorf("query = %q, want %q", cc.query, tc.wantQuery)
			}
			if cc.provider != tc.wantProvider {
				t.Errorf("provider = %q, want %q", cc.provider, tc.wantProvider)
			}
		})
	}
}

// fakeSource is a deterministic remote.Source used to drive the server without
// touching the network.
type fakeSource struct {
	name string
	out  []provider.Candidate
}

func (f fakeSource) Name() string { return f.name }
func (f fakeSource) Search(_ context.Context, query string) ([]provider.Candidate, error) {
	// Echo the query into the first candidate name so the test can assert the
	// value plumbed all the way through the protocol.
	out := make([]provider.Candidate, len(f.out))
	copy(out, f.out)
	if len(out) > 0 {
		out[0].Name = query + out[0].Name
	}
	return out, nil
}

func TestServeCompletionRoundTrip(t *testing.T) {
	// Wire an in-memory client<->server transport.
	cToS := newPipe()
	sToC := newPipe()

	reg := provider.NewRegistry()
	rem := remote.NewRegistry()
	rem.Register(fakeSource{name: "npm", out: []provider.Candidate{
		{Name: "-pad", Version: "1.3.0", Description: "left pad"},
	}})

	srv := New(reg, io.Discard).WithRemote(rem).WithVersion("test")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- srv.Serve(ctx, cToS.reader, sToC.writer) }()

	cw := sToC.reader // client reads server output here
	client := &testClient{r: bufio.NewReader(cw), w: cToS.writer, t: t}

	// initialize
	client.request(1, "initialize", initializeParams{})
	initResp := client.response()
	if initResp.Error != nil {
		t.Fatalf("initialize error: %v", initResp.Error)
	}

	client.notify("initialized", struct{}{})

	// open a document. The cursor will sit between the quotes of an empty
	// package name on line 1, inside an object pinned to the npm provider.
	doc := "packages: [\n\t{name: \"\", provider: \"npm\"},\n]"
	client.notify("textDocument/didOpen", didOpenParams{
		TextDocument: textDocumentItem{URI: "file:///pulipil.cue", LanguageID: "cue", Version: 1, Text: doc},
	})

	// Character 9 on line 1 is immediately after the opening quote of `name`:
	// "\t{name: \"" is 9 characters (tab + `{name: ` + `"`).
	client.request(2, "textDocument/completion", completionParams{
		TextDocument: textDocumentIdentifier{URI: "file:///pulipil.cue"},
		Position:     position{Line: 1, Character: 9},
	})

	resp := client.response()
	if resp.Error != nil {
		t.Fatalf("completion error: %v", resp.Error)
	}
	var list completionList
	if err := json.Unmarshal(resp.Result, &list); err != nil {
		t.Fatalf("decode completion list: %v", err)
	}
	if len(list.Items) == 0 {
		t.Fatal("expected at least one completion item")
	}
	// The fake source prefixes the query; with an empty query the label is
	// just "-pad".
	if list.Items[0].Label != "-pad" {
		t.Errorf("label = %q, want %q", list.Items[0].Label, "-pad")
	}
	if !strings.Contains(list.Items[0].Detail, "1.3.0") {
		t.Errorf("detail = %q, want it to contain the version", list.Items[0].Detail)
	}

	// shutdown / exit
	client.request(3, "shutdown", nil)
	_ = client.response()
	client.notify("exit", nil)

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Serve returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("server did not exit after `exit`")
	}
}

// --- tiny in-memory transport + client for the round-trip test ------------

// pipe is a unidirectional byte channel backed by io.Pipe.
type pipe struct {
	reader *io.PipeReader
	writer *io.PipeWriter
}

func newPipe() *pipe {
	r, w := io.Pipe()
	return &pipe{reader: r, writer: w}
}

type testClient struct {
	r *bufio.Reader
	w io.Writer
	t *testing.T
}

func (c *testClient) send(msg rpcMessage) {
	c.t.Helper()
	msg.JSONRPC = jsonrpcVersion
	body, err := json.Marshal(msg)
	if err != nil {
		c.t.Fatalf("marshal: %v", err)
	}
	if _, err := fmt.Fprintf(c.w, "Content-Length: %d\r\n\r\n", len(body)); err != nil {
		c.t.Fatalf("write header: %v", err)
	}
	if _, err := c.w.Write(body); err != nil {
		c.t.Fatalf("write body: %v", err)
	}
}

func (c *testClient) request(id int, method string, params any) {
	c.t.Helper()
	raw, _ := json.Marshal(params)
	idRaw := json.RawMessage(strconv.Itoa(id))
	c.send(rpcMessage{ID: &idRaw, Method: method, Params: raw})
}

func (c *testClient) notify(method string, params any) {
	c.t.Helper()
	raw, _ := json.Marshal(params)
	c.send(rpcMessage{Method: method, Params: raw})
}

func (c *testClient) response() rpcMessage {
	c.t.Helper()
	length := -1
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			c.t.Fatalf("read header: %v", err)
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		if name, value, ok := strings.Cut(line, ":"); ok && strings.EqualFold(strings.TrimSpace(name), "Content-Length") {
			length, _ = strconv.Atoi(strings.TrimSpace(value))
		}
	}
	if length < 0 {
		c.t.Fatal("response missing Content-Length")
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(c.r, body); err != nil {
		c.t.Fatalf("read body: %v", err)
	}
	var msg rpcMessage
	if err := json.Unmarshal(body, &msg); err != nil {
		c.t.Fatalf("unmarshal response: %v", err)
	}
	return msg
}
