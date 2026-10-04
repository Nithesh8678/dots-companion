#!/bin/bash
set -euo pipefail
DOTS_SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DOTS_SOURCE_ROOT"
mkdir -p dist
# Explicit allowlist: never include .build, user preferences, Keychain data, or app archives.
zip -q -r "dist/Dots Companion Source.zip" Package.swift README.md .gitignore Sources Tests Resources scripts docs
unzip -t "dist/Dots Companion Source.zip" | tail -1
