#!/usr/bin/env python3
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[1]
CHECKER = REPOSITORY / "scripts" / "check_publish_workflow.py"


class CheckPublishWorkflowTests(unittest.TestCase):
    def run_checker(self, workspace: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, CHECKER],
            cwd=workspace,
            text=True,
            capture_output=True,
            check=False,
        )

    def copy_workspace(self, workspace: Path) -> None:
        shutil.copytree(REPOSITORY / ".github", workspace / ".github")
        shutil.copytree(REPOSITORY / "files", workspace / "files")

    def test_rejects_unterminated_composite_action_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            workspace = Path(tempdir)
            self.copy_workspace(workspace)

            action = workspace / ".github/actions/generate-bst-ci-config/action.yml"
            action.write_text(
                "runs:\n"
                "  using: composite\n"
                "  steps:\n"
                "    - shell: bash\n"
                "      run: |\n"
                "        echo setup\n"
                "\n"
                "        if true; then\n"
                "          echo broken\n"
            )

            result = self.run_checker(workspace)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_rejects_optional_nvidia_publication(self) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            workspace = Path(tempdir)
            self.copy_workspace(workspace)

            publish = workspace / ".github/workflows/publish.yml"
            publish.write_text(
                publish.read_text().replace(
                    "sbom_filename: dakota-nvidia.spdx.json\n            continue: false",
                    "sbom_filename: dakota-nvidia.spdx.json\n            continue: true",
                    1,
                )
            )

            result = self.run_checker(workspace)

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
