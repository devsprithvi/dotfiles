package config

import "testing"

func TestParseValid(t *testing.T) {
	src := `
defaults: providers: ["dnf", "apt"]
packages: [
	{name: "git"},
	{name: "ripgrep", provider: "dnf", version: "14.0"},
	{name: "nano", state: "absent"},
]
`
	cfg, err := Parse([]byte(src), "test.cue")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(cfg.Packages) != 3 {
		t.Fatalf("want 3 packages, got %d", len(cfg.Packages))
	}
	if cfg.Packages[0].State != StatePresent {
		t.Fatalf("default state should be present, got %q", cfg.Packages[0].State)
	}
	if cfg.Packages[2].State != StateAbsent {
		t.Fatalf("want absent, got %q", cfg.Packages[2].State)
	}
}

func TestParseCustomProvider(t *testing.T) {
	src := `
providers: pipx: {
	binary:  "pipx"
	install: ["pipx", "install", "{{.Name}}"]
}
packages: [{name: "httpie", provider: "pipx"}]
`
	cfg, err := Parse([]byte(src), "test.cue")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	p, ok := cfg.Providers["pipx"]
	if !ok {
		t.Fatal("pipx provider not decoded")
	}
	if len(p.Install) != 3 {
		t.Fatalf("want 3 install args, got %v", p.Install)
	}
}

func TestParseRejectsMissingName(t *testing.T) {
	src := `packages: [{provider: "dnf"}]`
	if _, err := Parse([]byte(src), "test.cue"); err == nil {
		t.Fatal("expected error for package missing required name")
	}
}

func TestParseRejectsUnknownState(t *testing.T) {
	src := `packages: [{name: "git", state: "banana"}]`
	if _, err := Parse([]byte(src), "test.cue"); err == nil {
		t.Fatal("expected error for invalid state value")
	}
}

func TestParseRejectsUnknownField(t *testing.T) {
	src := `packages: [{name: "git", frobnicate: true}]`
	if _, err := Parse([]byte(src), "test.cue"); err == nil {
		t.Fatal("expected error for unknown field in closed schema")
	}
}

func TestParseCommands(t *testing.T) {
	src := `
packages: [{name: "git"}]
commands: [
	{name: "clone", run: ["git", "clone", "https://example.com/x"], needs: ["git"]},
	{name: "build", run: ["make", "-j"], needs: ["clone"], shell: true, trigger: "onchange"},
]
`
	cfg, err := Parse([]byte(src), "test.cue")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(cfg.Commands) != 2 {
		t.Fatalf("want 2 commands, got %d", len(cfg.Commands))
	}
	if cfg.Commands[0].Trigger != TriggerOnce {
		t.Fatalf("default trigger should be once, got %q", cfg.Commands[0].Trigger)
	}
	if cfg.Commands[1].Trigger != TriggerOnChange || !cfg.Commands[1].Shell {
		t.Fatalf("second command fields not decoded: %+v", cfg.Commands[1])
	}
	if len(cfg.Commands[0].Needs) != 1 || cfg.Commands[0].Needs[0] != "git" {
		t.Fatalf("needs not decoded: %+v", cfg.Commands[0].Needs)
	}
}

func TestParseCommandsOnlyConfig(t *testing.T) {
	// A config with commands but no packages must validate.
	src := `commands: [{name: "hello", run: ["echo", "hi"]}]`
	cfg, err := Parse([]byte(src), "test.cue")
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if len(cfg.Commands) != 1 || len(cfg.Packages) != 0 {
		t.Fatalf("unexpected decode: %+v", cfg)
	}
}

func TestParseRejectsEmptyRun(t *testing.T) {
	src := `commands: [{name: "bad", run: []}]`
	if _, err := Parse([]byte(src), "test.cue"); err == nil {
		t.Fatal("expected error for empty run argv")
	}
}
