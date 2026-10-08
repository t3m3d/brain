#!/usr/bin/env kr
// Build a sandboxed text-editor preview; distribution signing comes later.
import "k:sh"
import "k:env"
import "scripts/build.k"
just run { buildStore() }
