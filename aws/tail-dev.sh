#!/bin/bash

# Simple development log tailer - redirects to container tail for dev
exec $(dirname "$0")/tail-container-dev.sh "$@"

