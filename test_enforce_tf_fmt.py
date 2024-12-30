import os
import tempfile
import unittest
from pathlib import Path
from git import Repo
import json
from unittest.mock import patch, MagicMock

from enforce_tf_fmt import TerraformFormatter


class TestTerraformFormatter(unittest.TestCase):
    def setUp(self):
        """Set up test environment with a proper Git repository structure."""
        # Create temporary directory for test
        self.test_dir = tempfile.mkdtemp()
        self.original_dir = os.getcwd()
        os.chdir(self.test_dir)

        # Initialize git repository
        self.repo = Repo.init(self.test_dir)

        # Configure git
        with self.repo.config_writer() as git_config:
            git_config.set_value('user', 'email', 'test@example.com')
            git_config.set_value('user', 'name', 'Test User')
            git_config.set_value('init', 'defaultBranch', 'master')

        # Create and commit an initial file
        Path('initial.txt').write_text('Initial commit')
        self.repo.index.add(['initial.txt'])
        self.repo.index.commit("Initial commit")

        # Clear environment variables
        os.environ.pop('INPUT_TERRAFORM_VERSION', None)
        os.environ.pop('GITHUB_TOKEN', None)

    def test_missing_terraform_version(self):
        """Test that missing Terraform version raises ValueError."""
        with self.assertRaises(ValueError):
            TerraformFormatter(terraform_version=None)

    def test_invalid_terraform_version(self):
        """Test invalid version format rejection."""
        formatter = TerraformFormatter(terraform_version="invalid")
        self.assertFalse(formatter.validate_inputs())

    @patch('subprocess.run')
    def test_malformed_terraform_file(self, mock_run):
        """Test detection of malformed Terraform files."""
        # Mock subprocess.run to simulate terraform fmt output
        mock_run.return_value = MagicMock(
            returncode=1,
            stdout="formatting differences found",
            stderr=""
        )

        # Create and commit a test file
        Path('main.tf').write_text('malformed { terraform }')
        self.repo.index.add(['main.tf'])
        self.repo.index.commit("Add malformed terraform file")

        formatter = TerraformFormatter(terraform_version="1.0.0")
        formatter.terraform_path = "terraform"  # Mock path

        changed_files = ['main.tf']
        success, results = formatter.check_formatting(changed_files)

        self.assertFalse(success)
        self.assertIn('main.tf', results)

    @patch('subprocess.run')
    def test_well_formatted_terraform_file(self, mock_run):
        """Test verification of well-formatted Terraform files."""
        # Mock subprocess.run to simulate terraform fmt success
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="",
            stderr=""
        )

        # Create and commit a test file
        Path('main.tf').write_text('resource "test" {}')
        self.repo.index.add(['main.tf'])
        self.repo.index.commit("Add well-formatted terraform file")

        formatter = TerraformFormatter(terraform_version="1.0.0")
        formatter.terraform_path = "terraform"  # Mock path

        changed_files = ['main.tf']
        success, results = formatter.check_formatting(changed_files)

        self.assertTrue(success)
        self.assertEqual(results, {})

    @patch('github.Github')
    def test_github_integration(self, mock_github):
        """Test GitHub integration with proper mocking."""
        # Configure mock
        mock_github.return_value.get_user.return_value = MagicMock()

        formatter = TerraformFormatter(
            terraform_version="1.0.0",
            github_token="fake-token"
        )

        # Create test event data
        event_path = Path(self.test_dir) / 'event.json'
        event_data = {
            'pull_request': {'number': 1},
            'repository': {'full_name': 'test/repo'}
        }
        event_path.write_text(json.dumps(event_data))
        os.environ['GITHUB_EVENT_PATH'] = str(event_path)

        self.assertTrue(formatter.validate_inputs())

    def tearDown(self):
        """Clean up test environment."""
        os.chdir(self.original_dir)
        import shutil
        shutil.rmtree(self.test_dir)


if __name__ == '__main__':
    unittest.main()
