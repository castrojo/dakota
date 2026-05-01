# Template: Rust/Cargo project built from source
#
# Instructions:
#   1. Replace TEMPLATE_NAME with the binary name
#   2. Replace GITHUB_ORG / GITHUB_REPO with upstream values
#   3. Set the track: pattern (usually 'v[0-9]*.[0-9]*.[0-9]*')
#   4. Run: just bst source track elements/bluefin/TEMPLATE_NAME.bst
#      This updates the git_repo ref AND regenerates the cargo2 crate list
#      from upstream Cargo.lock — no separate generator step needed.
#
#   NOTE for brand-new elements with no existing cargo2 block:
#   bst source track cannot create a cargo2 block from nothing.
#   Bootstrap the initial cargo2 block with:
#     cd /tmp && git clone https://github.com/GITHUB_ORG/GITHUB_REPO
#     python3 files/scripts/generate_cargo_sources.py GITHUB_REPO/Cargo.lock
#   Paste the output below, then run: just bst source track elements/bluefin/TEMPLATE_NAME.bst
#
#   5. Add bluefin/TEMPLATE_NAME.bst to elements/bluefin/deps.bst
#   6. Run: just validate elements/bluefin/TEMPLATE_NAME.bst
#   7. Run: just bst build elements/bluefin/TEMPLATE_NAME.bst
#   8. Add to .github/workflows/track-bst-sources.yml under manual-merge matrix
#
# Ongoing updates: bst source track handles both git_repo ref AND cargo2 crates
# automatically once the element is in the CI tracking matrix.

kind: make

build-depends:
- freedesktop-sdk.bst:components/rust.bst
- freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

config:
  build-commands:
  - cargo build --release

  install-commands:
  - install -Dm755 target/release/TEMPLATE_NAME "%{install-root}%{bindir}/TEMPLATE_NAME"
  - |
    %{install-extra}

sources:
- kind: git_repo
  url: github:GITHUB_ORG/GITHUB_REPO.git
  track: 'v[0-9]*.[0-9]*.[0-9]*'
  ref: PLACEHOLDER_REF  # vVERSION
- kind: cargo2
  url: crates:crates
  ref:
  # Bootstrap: python3 files/scripts/generate_cargo_sources.py Cargo.lock
  # After bootstrap: just bst source track updates this block automatically
