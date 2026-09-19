package provider

import (
	"context"
	"reflect"
	"testing"
)

// fakeRunner records invocations and returns programmed results.
type fakeRunner struct {
	calls   [][]string
	result  Result
	err     error
	byIndex []Result
}

func (f *fakeRunner) Run(_ context.Context, argv []string, _ RunOpts) (Result, error) {
	f.calls = append(f.calls, argv)
	if f.byIndex != nil && len(f.calls) <= len(f.byIndex) {
		return f.byIndex[len(f.calls)-1], f.err
	}
	return f.result, f.err
}

func dnfSpec() Spec {
	return Spec{
		Name:         "dnf",
		Binary:       "dnf",
		RequiresRoot: true,
		Install:      []string{"dnf", "install", "-y", "{{.Name}}{{if .Version}}-{{.Version}}{{end}}"},
		Remove:       []string{"dnf", "remove", "-y", "{{.Name}}"},
		Check:        []string{"rpm", "-q", "{{.Name}}"},
	}
}

func TestInstallRendersVersionlessArgv(t *testing.T) {
	fr := &fakeRunner{}
	p := New(dnfSpec(), fr)
	if err := p.Install(context.Background(), Package{Name: "git"}); err != nil {
		t.Fatalf("install: %v", err)
	}
	want := []string{"dnf", "install", "-y", "git"}
	if !reflect.DeepEqual(fr.calls[0], want) {
		t.Fatalf("argv = %v, want %v", fr.calls[0], want)
	}
}

func TestInstallRendersConditionalVersion(t *testing.T) {
	fr := &fakeRunner{}
	p := New(dnfSpec(), fr)
	if err := p.Install(context.Background(), Package{Name: "git", Version: "2.43"}); err != nil {
		t.Fatalf("install: %v", err)
	}
	want := []string{"dnf", "install", "-y", "git-2.43"}
	if !reflect.DeepEqual(fr.calls[0], want) {
		t.Fatalf("argv = %v, want %v", fr.calls[0], want)
	}
}

func TestInstallAppendsExtraArgs(t *testing.T) {
	fr := &fakeRunner{}
	p := New(dnfSpec(), fr)
	if err := p.Install(context.Background(), Package{Name: "git", Args: []string{"--allowerasing"}}); err != nil {
		t.Fatalf("install: %v", err)
	}
	want := []string{"dnf", "install", "-y", "git", "--allowerasing"}
	if !reflect.DeepEqual(fr.calls[0], want) {
		t.Fatalf("argv = %v, want %v", fr.calls[0], want)
	}
}

func TestInstallNonZeroExitIsError(t *testing.T) {
	fr := &fakeRunner{result: Result{ExitCode: 1}}
	p := New(dnfSpec(), fr)
	if err := p.Install(context.Background(), Package{Name: "git"}); err == nil {
		t.Fatal("expected error on non-zero exit")
	}
}

func TestIsInstalled(t *testing.T) {
	present := New(dnfSpec(), &fakeRunner{result: Result{ExitCode: 0}})
	if ok, known := present.IsInstalled(context.Background(), Package{Name: "git"}); !ok || !known {
		t.Fatalf("want installed+known, got ok=%v known=%v", ok, known)
	}
	absent := New(dnfSpec(), &fakeRunner{result: Result{ExitCode: 1}})
	if ok, known := absent.IsInstalled(context.Background(), Package{Name: "git"}); ok || !known {
		t.Fatalf("want absent+known, got ok=%v known=%v", ok, known)
	}
}

func TestIsInstalledUnknownWithoutCheck(t *testing.T) {
	spec := dnfSpec()
	spec.Check = nil
	p := New(spec, &fakeRunner{})
	if _, known := p.IsInstalled(context.Background(), Package{Name: "git"}); known {
		t.Fatal("want unknown when no check command is defined")
	}
}

func TestRemoveUnsupported(t *testing.T) {
	spec := dnfSpec()
	spec.Remove = nil
	p := New(spec, &fakeRunner{})
	if err := p.Remove(context.Background(), Package{Name: "git"}); err == nil {
		t.Fatal("expected ErrUnsupported for missing remove command")
	}
}

func TestSearchParsesLines(t *testing.T) {
	spec := dnfSpec()
	spec.Search = []string{"dnf", "search", "{{.Query}}"}
	fr := &fakeRunner{result: Result{ExitCode: 0, Stdout: "ripgrep : fast grep\nripgrep-all : more"}}
	p := New(spec, fr)
	got, err := p.Search(context.Background(), "ripgrep")
	if err != nil {
		t.Fatalf("search: %v", err)
	}
	if len(got) != 2 || got[0].Name != "ripgrep" {
		t.Fatalf("unexpected candidates: %+v", got)
	}
}
