#!/bin/sh
# bootstrap-env.sh: Ensures .env exists before running make

if [ ! -f .env ]; then
  echo "INFO: .env not found, creating from .env.example"
  cp .env.example .env
fi

exec make "$@"
