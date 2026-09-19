package config

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"

	"cuelang.org/go/cue"
	"cuelang.org/go/cue/cuecontext"
	"cuelang.org/go/cue/errors"
)

//go:embed schema/pulipil.cue
var schemaSource string

// SchemaSource returns the embedded CUE schema text.
func SchemaSource() string { return schemaSource }

// DefaultFilenames are the paths searched, in order, when no explicit config
// path is provided.
var DefaultFilenames = []string{"pulipil.cue", ".pulipil.cue", "config.cue"}

// Discover returns the first existing default config file in dir, or "" if
// none is found.
func Discover(dir string) string {
	for _, name := range DefaultFilenames {
		p := filepath.Join(dir, name)
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
	}
	return ""
}

// Load reads, validates against the embedded schema, and decodes the config
// file at path.
func Load(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}
	return Parse(data, path)
}

// Parse validates and decodes config bytes. The name is used only for error
// messages.
func Parse(data []byte, name string) (*Config, error) {
	ctx := cuecontext.New()

	schema := ctx.CompileString(schemaSource, cue.Filename("pulipil.schema.cue"))
	if err := schema.Err(); err != nil {
		return nil, fmt.Errorf("internal schema error: %s", errors.Details(err, nil))
	}

	user := ctx.CompileBytes(data, cue.Filename(name))
	if err := user.Err(); err != nil {
		return nil, fmt.Errorf("invalid config: %s", errors.Details(err, nil))
	}

	configDef := schema.LookupPath(cue.ParsePath("#Config"))
	if err := configDef.Err(); err != nil {
		return nil, fmt.Errorf("internal schema error: %s", errors.Details(err, nil))
	}

	unified := configDef.Unify(user)
	if err := unified.Validate(cue.Concrete(true), cue.All()); err != nil {
		return nil, fmt.Errorf("config validation failed:\n%s", errors.Details(err, nil))
	}

	var cfg Config
	if err := unified.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("decode config: %s", errors.Details(err, nil))
	}
	normalize(&cfg)
	return &cfg, nil
}

// normalize fills defaults that the decoder may leave empty.
func normalize(cfg *Config) {
	for i := range cfg.Packages {
		if cfg.Packages[i].State == "" {
			cfg.Packages[i].State = StatePresent
		}
	}
	for i := range cfg.Commands {
		if cfg.Commands[i].Trigger == "" {
			cfg.Commands[i].Trigger = TriggerOnce
		}
	}
}
