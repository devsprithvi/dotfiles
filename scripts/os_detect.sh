#!/usr/bin/env bash

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Windows;;
    MINGW*)     machine=Windows;;
    MSYS*)      machine=Windows;;
    *)          machine="UNKNOWN:${OS}"
esac
export machine
