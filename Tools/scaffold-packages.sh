#!/usr/bin/env bash
# One-time scaffolding script for NSP-001. Generates the 11 empty-but-compiling
# Swift packages under Packages/ per docs/01-ARCHITECTURE.md §3 and the
# dependency graph in CLAUDE.md §3. Safe to re-run; it overwrites generated
# placeholder files only, never hand-written module content.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT/Packages"

# name:dep1,dep2,...  (deps may be empty)
modules=(
  "NSPCore:"
  "NSPPersistence:NSPCore"
  "NSPPolicy:NSPCore"
  "NSPMedia:NSPPersistence,NSPPolicy"
  "NSPTransfer:NSPMedia"
  "NSPSync:NSPTransfer"
  "NSPIntelligence:NSPSync"
  "NSPBackendClient:NSPCore,NSPPolicy"
  "NSPActions:NSPIntelligence,NSPPolicy"
  "NSPDesignSystem:NSPCore"
  "NSPTestSupport:NSPCore,NSPPersistence,NSPMedia,NSPTransfer,NSPSync,NSPIntelligence,NSPPolicy,NSPBackendClient,NSPActions"
)

for entry in "${modules[@]}"; do
  name="${entry%%:*}"
  deps="${entry#*:}"
  dir="$PKG_DIR/$name"
  mkdir -p "$dir/Sources/$name" "$dir/Tests/${name}Tests"

  # Build the dependencies array for Package.swift
  pkg_deps=""
  target_deps=""
  if [ -n "$deps" ]; then
    IFS=',' read -ra dep_arr <<< "$deps"
    for d in "${dep_arr[@]}"; do
      pkg_deps="${pkg_deps}        .package(path: \"../${d}\"),\n"
      target_deps="${target_deps}                .product(name: \"${d}\", package: \"${d}\"),\n"
    done
  fi

  printf '// swift-tools-version: 6.0\nimport PackageDescription\n\nlet package = Package(\n    name: "%s",\n    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],\n    products: [\n        .library(name: "%s", targets: ["%s"]),\n    ],\n    dependencies: [\n%b    ],\n    targets: [\n        .target(\n            name: "%s",\n            dependencies: [\n%b            ],\n            swiftSettings: [.swiftLanguageMode(.v6)]\n        ),\n        .testTarget(\n            name: "%sTests",\n            dependencies: ["%s"],\n            swiftSettings: [.swiftLanguageMode(.v6)]\n        ),\n    ]\n)\n' \
    "$name" "$name" "$name" "$pkg_deps" "$name" "$target_deps" "$name" "$name" \
    > "$dir/Package.swift"

  if [ ! -f "$dir/Sources/$name/$name.swift" ]; then
    printf '/// Marker type confirming the %s module target compiles and links.\n///\n/// Real domain logic lands ticket by ticket per docs/09-BACKLOG.md; this file\n/// is replaced incrementally, never deleted wholesale.\npublic enum %sModule {\n    public static let name = "%s"\n}\n' \
      "$name" "$name" "$name" > "$dir/Sources/$name/$name.swift"
  fi

  if [ ! -f "$dir/Tests/${name}Tests/${name}Tests.swift" ]; then
    printf 'import Testing\n@testable import %s\n\n@Suite("%s module")\nstruct %sTests {\n    @Test func test_module_name_matchesPackage() {\n        #expect(%sModule.name == "%s")\n    }\n}\n' \
      "$name" "$name" "$name" "$name" "$name" > "$dir/Tests/${name}Tests/${name}Tests.swift"
  fi

  echo "scaffolded $name (deps: ${deps:-none})"
done
