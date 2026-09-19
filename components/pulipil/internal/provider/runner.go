package provider

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// RunOpts controls how a single command invocation is executed.
type RunOpts struct {
	// Root requests privilege elevation (sudo) when the current user is not
	// already root. Ignored on Windows.
	Root bool
	// Env holds additional environment variables for the process.
	Env map[string]string
	// Stream, when true, connects the child's stdout/stderr to the parent
	// process so long-running installs show live output.
	Stream bool
	// Dir sets the working directory for the process. Empty inherits the
	// parent's working directory.
	Dir string
}

// Result captures the outcome of a command invocation.
type Result struct {
	ExitCode int
	Stdout   string
	Stderr   string
}

// OK reports a zero exit code.
func (r Result) OK() bool { return r.ExitCode == 0 }

// Runner executes rendered command argv slices. It is an interface so the
// engine can substitute a dry-run implementation that only records intent.
type Runner interface {
	Run(ctx context.Context, argv []string, opts RunOpts) (Result, error)
}

// ExecRunner is the default Runner backed by os/exec.
type ExecRunner struct {
	// SudoPath overrides the auto-detected sudo binary (mainly for tests).
	SudoPath string
}

// NewExecRunner returns a Runner that shells out to real commands.
func NewExecRunner() *ExecRunner { return &ExecRunner{} }

// Run executes argv, optionally elevating privileges and streaming output.
func (e *ExecRunner) Run(ctx context.Context, argv []string, opts RunOpts) (Result, error) {
	if len(argv) == 0 {
		return Result{}, ErrEmptyCommand
	}

	argv = e.maybeElevate(opts, argv)

	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Env = os.Environ()
	for k, v := range opts.Env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	if opts.Dir != "" {
		cmd.Dir = opts.Dir
	}

	var outBuf, errBuf bytes.Buffer
	if opts.Stream {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stdout = &outBuf
		cmd.Stderr = &errBuf
	}

	err := cmd.Run()
	res := Result{
		ExitCode: cmd.ProcessState.ExitCode(),
		Stdout:   strings.TrimRight(outBuf.String(), "\n"),
		Stderr:   strings.TrimRight(errBuf.String(), "\n"),
	}
	if err != nil {
		if _, ok := err.(*exec.ExitError); ok {
			// A non-zero exit is reported via ExitCode, not as a Go error.
			return res, nil
		}
		return res, err
	}
	return res, nil
}

// maybeElevate prepends sudo when root is required and available.
func (e *ExecRunner) maybeElevate(opts RunOpts, argv []string) []string {
	if !opts.Root || runtime.GOOS == "windows" || os.Geteuid() == 0 {
		return argv
	}
	sudo := e.SudoPath
	if sudo == "" {
		if p, err := exec.LookPath("sudo"); err == nil {
			sudo = p
		}
	}
	if sudo == "" {
		return argv // best effort; command will likely fail with a clear error
	}
	return append([]string{sudo}, argv...)
}
