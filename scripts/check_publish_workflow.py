#!/usr/bin/env python3
from pathlib import Path
import re
import sys

publish = Path('.github/workflows/publish.yml').read_text()
errors = []

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

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    sys.exit(1)

print('publish workflow SBOM path looks sane')
