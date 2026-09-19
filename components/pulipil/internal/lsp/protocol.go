package lsp

import "encoding/json"

// This file defines the minimal slice of the JSON-RPC 2.0 and Language Server
// Protocol wire types that pulipil's server needs. Keeping them local (rather
// than pulling a large LSP dependency) keeps the server auditable and the
// binary small; the shapes below match the LSP 3.17 specification.

// jsonrpcVersion is the only version we speak.
const jsonrpcVersion = "2.0"

// rpcMessage is a single JSON-RPC frame. It doubles as request, response and
// notification; unused fields are omitted on the wire.
type rpcMessage struct {
	JSONRPC string           `json:"jsonrpc"`
	ID      *json.RawMessage `json:"id,omitempty"`
	Method  string           `json:"method,omitempty"`
	Params  json.RawMessage  `json:"params,omitempty"`
	Result  json.RawMessage  `json:"result,omitempty"`
	Error   *rpcError        `json:"error,omitempty"`
}

// isNotification reports whether the message carries no id (fire-and-forget).
func (m *rpcMessage) isNotification() bool { return m.ID == nil }

// rpcError is the JSON-RPC error object.
type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

func (e *rpcError) Error() string { return e.Message }

// Standard JSON-RPC / LSP error codes used by the server.
const (
	codeParseError     = -32700
	codeInvalidRequest = -32600
	codeMethodNotFound = -32601
	codeInvalidParams  = -32602
	codeInternalError  = -32603
	codeServerNotInit  = -32002
)

// --- LSP core types -------------------------------------------------------

type position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

type textDocumentIdentifier struct {
	URI string `json:"uri"`
}

type textDocumentItem struct {
	URI        string `json:"uri"`
	LanguageID string `json:"languageId"`
	Version    int    `json:"version"`
	Text       string `json:"text"`
}

// --- Lifecycle ------------------------------------------------------------

type initializeParams struct {
	ProcessID    any             `json:"processId"`
	ClientInfo   *clientInfo     `json:"clientInfo,omitempty"`
	RootURI      string          `json:"rootUri"`
	Capabilities json.RawMessage `json:"capabilities"`
}

type clientInfo struct {
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
}

type initializeResult struct {
	Capabilities serverCapabilities `json:"capabilities"`
	ServerInfo   serverInfo         `json:"serverInfo"`
}

type serverInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type serverCapabilities struct {
	TextDocumentSync   int                `json:"textDocumentSync"`
	CompletionProvider *completionOptions `json:"completionProvider,omitempty"`
	HoverProvider      bool               `json:"hoverProvider"`
}

type completionOptions struct {
	TriggerCharacters []string `json:"triggerCharacters,omitempty"`
	ResolveProvider   bool     `json:"resolveProvider"`
}

// textDocumentSyncFull requests the whole document text on every change. It is
// the simplest correct mode and fine for the small pulipil.cue files we serve.
const textDocumentSyncFull = 1

// --- Document sync --------------------------------------------------------

type didOpenParams struct {
	TextDocument textDocumentItem `json:"textDocument"`
}

type didChangeParams struct {
	TextDocument struct {
		URI     string `json:"uri"`
		Version int    `json:"version"`
	} `json:"textDocument"`
	ContentChanges []struct {
		Text string `json:"text"`
	} `json:"contentChanges"`
}

type didCloseParams struct {
	TextDocument textDocumentIdentifier `json:"textDocument"`
}

// --- Completion -----------------------------------------------------------

type completionParams struct {
	TextDocument textDocumentIdentifier `json:"textDocument"`
	Position     position               `json:"position"`
}

// completionItemKind values (subset) from the LSP spec.
const (
	kindModule = 9
	kindValue  = 12
)

type completionItem struct {
	Label         string `json:"label"`
	Kind          int    `json:"kind,omitempty"`
	Detail        string `json:"detail,omitempty"`
	Documentation string `json:"documentation,omitempty"`
	InsertText    string `json:"insertText,omitempty"`
	SortText      string `json:"sortText,omitempty"`
}

type completionList struct {
	IsIncomplete bool             `json:"isIncomplete"`
	Items        []completionItem `json:"items"`
}
