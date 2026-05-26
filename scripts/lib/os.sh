#!/usr/bin/env bash

OS_NAME="$(uname -s)"

case "${OS_NAME}" in
    Linux*) machine=Linux ;;
    Darwin*) machine=Mac ;;
    CYGWIN*|MINGW*|MSYS*) machine=Windows ;;
    *) machine="UNKNOWN:${OS_NAME}" ;;
esac

export machine
