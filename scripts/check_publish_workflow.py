#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import sys
import textwrap

publish = Path('.github/workflows/publish.yml').read_text()
install_defaults = Path('files/bootc-install/00-defaults.toml').read_text()
ci_config_action = Path('.github/actions/generate-bst-ci-config/action.yml').read_text()

match = re.search(
    r'- name: Install image to disk via bootc\n(?P<body>.*?)(?:\n\s*- name: |\n\s*# ──)',
    publish,
    re.S,
)
if not match:
    print('could not find boot-check install step in .github/workflows/publish.yml', file=sys.stderr)
    sys.exit(1)

body = match.group('body')
errors = []

required = [
    '--via-loopback /data/disk.raw',
    '--wipe',
]
for token in required:
    if token not in body:
        errors.append(f'missing {token!r} in boot-check install step')

forbidden = [
    '--generic-image',
    '--filesystem xfs',
]
for token in forbidden:
    if token in body:
        errors.append(f'unexpected {token!r} in boot-check install step')

if 'bootloader = "systemd"' not in install_defaults:
    errors.append('files/bootc-install/00-defaults.toml must set bootloader = "systemd"')
if 'type = "xfs"' not in install_defaults:
    errors.append('files/bootc-install/00-defaults.toml must set root filesystem type = "xfs"')

shell = None
run_indent = None
shell_lines = []
for line in ci_config_action.splitlines(keepends=True):
    if run_indent is None:
        match = re.match(r'^(?P<indent> *)run: \|\s*$', line)
        if match:
            run_indent = len(match.group('indent'))
        continue

    if line.strip() and len(line) - len(line.lstrip()) <= run_indent:
        break
    shell_lines.append(line)

if run_indent is None:
    errors.append('could not find composite action shell in generate-bst-ci-config')
else:
    shell = textwrap.dedent(''.join(shell_lines))
    shell_check = subprocess.run(
        ['bash', '-n'],
        input=shell,
        text=True,
        capture_output=True,
        check=False,
    )
    if shell_check.returncode:
        errors.append(
            'generate-bst-ci-config shell is invalid: '
            f'{shell_check.stderr.strip()}'
        )

sbom_match = re.search(
    r'publish-sbom:\n(?P<body>.*?)(?:\n\S|\Z)',
    publish,
    re.S,
)
if not sbom_match:
    errors.append('could not find publish-sbom job in .github/workflows/publish.yml')
else:
    sbom_body = sbom_match.group('body')
    default_continue = re.search(
        r'- variant: default\n\s+element: oci/bluefin\.bst\n\s+image_suffix: \'\'\n\s+sbom_filename: dakota\.spdx\.json\n\s+continue: true',
        sbom_body,
    )
    if not default_continue:
        errors.append('publish-sbom default variant must stay continue-on-error via continue: true')
    if 'continue-on-error: ${{ matrix.continue }}' not in sbom_body:
        errors.append('publish-sbom job must wire continue-on-error: ${{ matrix.continue }}')

publish_image_match = re.search(
    r'  publish-image:\n(?P<body>.*?)(?:\n  [a-z][a-z-]+:|\Z)',
    publish,
    re.S,
)
if not publish_image_match:
    errors.append('could not find publish-image job in .github/workflows/publish.yml')
else:
    publish_image_body = publish_image_match.group('body')
    nvidia_required = re.search(
        r'- variant: nvidia\n'
        r'\s+element: oci/bluefin-nvidia\.bst\n'
        r"\s+image_suffix: '-nvidia'\n"
        r'\s+sbom_filename: dakota-nvidia\.spdx\.json\n'
        r'\s+continue: false',
        publish_image_body,
    )
    if not nvidia_required:
        errors.append('publish-image nvidia variant must be required')

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    sys.exit(1)

print('publish workflow boot-check install path looks sane')
