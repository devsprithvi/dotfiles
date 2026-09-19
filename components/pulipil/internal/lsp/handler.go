package lsp

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"sync"
)

// handler owns the per-connection state: the open-document store and the
// initialize/shutdown lifecycle flags. One handler serves one client.
type handler struct {
	srv  *Server
	conn *conn

	mu           sync.RWMutex
	docs         map[string]string // uri -> full text
	initialized  bool
	shuttingDown bool
}

func newHandler(srv *Server, c *conn) *handler {
	return &handler{srv: srv, conn: c, docs: make(map[string]string)}
}

// run is the message loop. It returns nil on a clean exit (client sent exit
// after shutdown) and an error on transport failure.
func (h *handler) run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		msg, err := h.conn.read()
		if err != nil {
			var fe *frameError
			if ok := asFrameError(err, &fe); ok {
				// Malformed JSON in a well-framed body: report and continue.
				_ = h.conn.replyError(nil, codeParseError, fe.Error())
				continue
			}
			// EOF or transport error ends the session.
			if h.shuttingDown {
				return nil
			}
			return err
		}

		if done, err := h.dispatch(ctx, msg); err != nil {
			return err
		} else if done {
			return nil
		}
	}
}

// dispatch routes one message. It returns done=true when the server should
// stop (the `exit` notification).
func (h *handler) dispatch(ctx context.Context, msg *rpcMessage) (done bool, err error) {
	switch msg.Method {
	case "initialize":
		return false, h.onInitialize(msg)
	case "initialized":
		h.setInitialized()
		return false, nil
	case "shutdown":
		h.mu.Lock()
		h.shuttingDown = true
		h.mu.Unlock()
		return false, h.conn.reply(msg.ID, nil)
	case "exit":
		return true, nil
	case "textDocument/didOpen":
		return false, h.onDidOpen(msg)
	case "textDocument/didChange":
		return false, h.onDidChange(msg)
	case "textDocument/didClose":
		return false, h.onDidClose(msg)
	case "textDocument/completion":
		return false, h.onCompletion(ctx, msg)
	default:
		// Ignore unknown notifications; answer unknown requests politely.
		if !msg.isNotification() {
			return false, h.conn.replyError(msg.ID, codeMethodNotFound, "unsupported method: "+msg.Method)
		}
		return false, nil
	}
}

func (h *handler) onInitialize(msg *rpcMessage) error {
	result := initializeResult{
		Capabilities: serverCapabilities{
			TextDocumentSync: textDocumentSyncFull,
			CompletionProvider: &completionOptions{
				// `"` opens a string value; `-` and `/` appear inside package
				// names (e.g. left-pad, @scope/pkg) so keep completing as typed.
				TriggerCharacters: []string{"\"", "-", "/", "@", "."},
				ResolveProvider:   false,
			},
			HoverProvider: false,
		},
		ServerInfo: serverInfo{Name: "pulipil-lsp", Version: h.srv.version},
	}
	return h.conn.reply(msg.ID, result)
}

func (h *handler) setInitialized() {
	h.mu.Lock()
	h.initialized = true
	h.mu.Unlock()
}

func (h *handler) onDidOpen(msg *rpcMessage) error {
	var p didOpenParams
	if err := json.Unmarshal(msg.Params, &p); err != nil {
		return nil // notifications cannot be answered with an error
	}
	h.mu.Lock()
	h.docs[p.TextDocument.URI] = p.TextDocument.Text
	h.mu.Unlock()
	return nil
}

func (h *handler) onDidChange(msg *rpcMessage) error {
	var p didChangeParams
	if err := json.Unmarshal(msg.Params, &p); err != nil {
		return nil
	}
	if len(p.ContentChanges) == 0 {
		return nil
	}
	// Full-sync mode: the last change carries the whole document.
	text := p.ContentChanges[len(p.ContentChanges)-1].Text
	h.mu.Lock()
	h.docs[p.TextDocument.URI] = text
	h.mu.Unlock()
	return nil
}

func (h *handler) onDidClose(msg *rpcMessage) error {
	var p didCloseParams
	if err := json.Unmarshal(msg.Params, &p); err != nil {
		return nil
	}
	h.mu.Lock()
	delete(h.docs, p.TextDocument.URI)
	h.mu.Unlock()
	return nil
}

func (h *handler) onCompletion(ctx context.Context, msg *rpcMessage) error {
	var p completionParams
	if err := json.Unmarshal(msg.Params, &p); err != nil {
		return h.conn.replyError(msg.ID, codeInvalidParams, err.Error())
	}

	h.mu.RLock()
	text := h.docs[p.TextDocument.URI]
	h.mu.RUnlock()

	cc, ok := analyze(text, p.Position)
	if !ok {
		// Not in a completable position: return an empty, complete list.
		return h.conn.reply(msg.ID, completionList{IsIncomplete: false, Items: nil})
	}

	candidates, err := h.srv.Complete(ctx, cc.provider, cc.query)
	if err != nil {
		// Surface as an empty list marked incomplete so the editor retries as
		// the user keeps typing, rather than a hard error popup.
		return h.conn.reply(msg.ID, completionList{IsIncomplete: true, Items: nil})
	}

	items := make([]completionItem, 0, len(candidates))
	for i, c := range candidates {
		detail := c.Version
		if detail == "" {
			detail = cc.sourceName
		} else {
			detail = c.Version + " · " + cc.sourceName
		}
		items = append(items, completionItem{
			Label:         c.Name,
			Kind:          kindValue,
			Detail:        detail,
			Documentation: c.Description,
			InsertText:    c.Name,
			// Preserve registry relevance order in the editor.
			SortText: fmt.Sprintf("%04d", i),
		})
	}
	return h.conn.reply(msg.ID, completionList{IsIncomplete: true, Items: items})
}

// --- completion context detection ----------------------------------------

// completionContext captures what the editor is asking us to complete.
type completionContext struct {
	provider   string // resolved provider/source name, "" means auto
	sourceName string // label shown in completion detail
	query      string // partial text already typed inside the string
}

var (
	// nameFieldRe matches a `name: "<partial>` string value under the cursor.
	nameFieldRe = regexp.MustCompile(`(?:^|[\s{,])name\s*:\s*"([^"]*)$`)
	// providerRe extracts a provider pin from the enclosing object text.
	providerRe = regexp.MustCompile(`provider\s*:\s*"([^"]+)"`)
)

// analyze inspects the document at pos and decides whether the cursor sits in a
// package `name` string, and if so which provider governs it. The provider is
// taken from the nearest enclosing `{ ... }` object so that
//
//	{ name: "ripg", provider: "crates" }
//
// completes crates.io names, while a bare `{ name: "wg" }` falls back to the
// default source order.
func analyze(text string, pos position) (completionContext, bool) {
	lines := strings.Split(text, "\n")
	if pos.Line < 0 || pos.Line >= len(lines) {
		return completionContext{}, false
	}
	line := lines[pos.Line]
	char := pos.Character
	if char > len(line) {
		char = len(line)
	}
	prefix := line[:char]

	m := nameFieldRe.FindStringSubmatch(prefix)
	if m == nil {
		return completionContext{}, false
	}
	query := m[1]

	provider := providerInEnclosingObject(text, offsetOf(lines, pos.Line, char))
	source := provider
	if source == "" {
		source = "auto"
	}
	return completionContext{provider: provider, sourceName: source, query: query}, true
}

// offsetOf converts a (line, character) position into an absolute byte offset.
func offsetOf(lines []string, line, char int) int {
	off := 0
	for i := 0; i < line && i < len(lines); i++ {
		off += len(lines[i]) + 1 // +1 for the split '\n'
	}
	return off + char
}

// providerInEnclosingObject finds the `{ ... }` object containing offset and
// returns its `provider:` pin, or "" if none. Braces inside string literals
// are rare in pulipil.cue and intentionally not special-cased.
func providerInEnclosingObject(text string, offset int) string {
	if offset > len(text) {
		offset = len(text)
	}
	// Walk left to the opening brace of the enclosing object.
	depth := 0
	start := -1
	for i := offset - 1; i >= 0; i-- {
		switch text[i] {
		case '}':
			depth++
		case '{':
			if depth == 0 {
				start = i
			} else {
				depth--
			}
		}
		if start >= 0 {
			break
		}
	}
	if start < 0 {
		return ""
	}
	// Walk right to the matching closing brace.
	depth = 0
	end := len(text)
	for i := start + 1; i < len(text); i++ {
		switch text[i] {
		case '{':
			depth++
		case '}':
			if depth == 0 {
				end = i
				i = len(text) // break
				continue
			}
			depth--
		}
	}
	obj := text[start:end]
	if m := providerRe.FindStringSubmatch(obj); m != nil {
		return m[1]
	}
	return ""
}

// asFrameError reports whether err is a *frameError, storing it in target.
func asFrameError(err error, target **frameError) bool {
	fe, ok := err.(*frameError)
	if ok {
		*target = fe
	}
	return ok
}
