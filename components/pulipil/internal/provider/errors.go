package provider

import "errors"

var (
	// ErrEmptyCommand is returned when a rendered command has no argv.
	ErrEmptyCommand = errors.New("provider: empty command")

	// ErrUnsupported is returned when a provider lacks a requested action
	// (for example a custom provider that defines no remove command).
	ErrUnsupported = errors.New("provider: operation not supported")
)
