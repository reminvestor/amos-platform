#!/bin/bash

# Simple production log tailer - redirects to container tail
exec $(dirname "$0")/tail-container.sh "$@"
