package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
)

// conn is a JSON-RPC 2.0 connection over an LSP-framed byte stream. Messages
// are prefixed with `Content-Length` headers terminated by a blank line, per
// the LSP base protocol. Writes are serialized so concurrent handlers (and
// server-initiated notifications) cannot interleave frames.
type conn struct {
	r  *bufio.Reader
	w  io.Writer
	wm sync.Mutex
}

func newConn(r io.Reader, w io.Writer) *conn {
	return &conn{r: bufio.NewReader(r), w: w}
}

// read blocks for the next message frame and decodes it.
func (c *conn) read() (*rpcMessage, error) {
	length, err := c.readHeaders()
	if err != nil {
		return nil, err
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(c.r, body); err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	var msg rpcMessage
	if err := json.Unmarshal(body, &msg); err != nil {
		return nil, &frameError{err: err}
	}
	return &msg, nil
}

// frameError marks a body that framed correctly but failed to parse, so the
// loop can answer with a JSON-RPC parse error instead of tearing down.
type frameError struct{ err error }

func (e *frameError) Error() string { return e.err.Error() }

// readHeaders parses the header block and returns the Content-Length.
func (c *conn) readHeaders() (int, error) {
	length := -1
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			return 0, err // typically io.EOF at shutdown
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break // end of headers
		}
		name, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		if strings.EqualFold(strings.TrimSpace(name), "Content-Length") {
			n, err := strconv.Atoi(strings.TrimSpace(value))
			if err != nil {
				return 0, fmt.Errorf("invalid Content-Length %q: %w", value, err)
			}
			length = n
		}
	}
	if length < 0 {
		return 0, fmt.Errorf("missing Content-Length header")
	}
	return length, nil
}

// write frames and sends a single message.
func (c *conn) write(msg *rpcMessage) error {
	msg.JSONRPC = jsonrpcVersion
	body, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("marshal message: %w", err)
	}
	c.wm.Lock()
	defer c.wm.Unlock()
	if _, err := fmt.Fprintf(c.w, "Content-Length: %d\r\n\r\n", len(body)); err != nil {
		return err
	}
	_, err = c.w.Write(body)
	return err
}

// reply sends a successful response carrying result for the given id.
func (c *conn) reply(id *json.RawMessage, result any) error {
	raw, err := json.Marshal(result)
	if err != nil {
		return err
	}
	return c.write(&rpcMessage{ID: id, Result: raw})
}

// replyError sends an error response for the given id.
func (c *conn) replyError(id *json.RawMessage, code int, message string) error {
	return c.write(&rpcMessage{ID: id, Error: &rpcError{Code: code, Message: message}})
}

// notify sends a server-initiated notification (no id).
func (c *conn) notify(method string, params any) error {
	raw, err := json.Marshal(params)
	if err != nil {
		return err
	}
	return c.write(&rpcMessage{Method: method, Params: raw})
}
