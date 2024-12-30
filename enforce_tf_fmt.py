import os
import sys
import logging
from pathlib import Path
import tempfile
import zipfile
from typing import List, Tuple, Optional
import json
import subprocess

import requests
from git import Repo, GitCommandError
from github import Github, GithubException
from github.Auth import Token

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class TerraformFormatter:
    def __init__(self, terraform_version: str, github_token: Optional[str] = None):
        """
        Initialize the formatter with required versions and tokens.

        Args:
            terraform_version: Specific version of Terraform to use (e.g., "1.5.0")
            github_token: GitHub API token for posting comments (optional)
        """
        if not terraform_version:
            logger.error("No Terraform version specified")
            raise ValueError("Terraform version is required")

        self.terraform_version = terraform_version
        self.github_token = github_token
        self.terraform_path = None
        self.repo = None
        self.gh_client = None

    def validate_inputs(self) -> bool:
        try:
            # Validate Terraform version format
            if not self._is_valid_version(self.terraform_version):
                logger.error("Invalid Terraform version format. Expected: X.Y.Z")
                return False

            # Validate Git repository
            try:
                self.repo = Repo(os.getcwd())
                if self.repo.bare:
                    logger.error("Current directory is not a Git repository")
                    return False
            except GitCommandError as e:
                logger.error(f"Git repository error: {str(e)}")
                return False

            # Initialize GitHub client if token provided
            if self.github_token:
                try:
                    # Use the new Token auth method
                    auth = Token(self.github_token)
                    self.gh_client = Github(auth=auth)
                    # Test the connection
                    self.gh_client.get_user().login
                except GithubException as e:
                    logger.error(f"GitHub authentication failed: {str(e)}")
                    return False

            return True

        except Exception as e:
            logger.error(f"Validation error: {str(e)}")
            return False

    def check_formatting(self, files: List[str]) -> Tuple[bool, dict]:
        """
        Check formatting for provided Terraform files using terraform fmt command directly.

        Args:
            files: List of Terraform files to check

        Returns:
            Tuple[bool, dict]: (success_status, formatting_results)
        """
        formatting_failed = False
        results = {}

        for file in files:
            try:
                # Run terraform fmt with check and diff flags
                result = subprocess.run(
                    [self.terraform_path, 'fmt', '-check', '-diff', file],
                    capture_output=True,
                    text=True
                )

                is_formatted = result.returncode == 0
                if not is_formatted:
                    formatting_failed = True
                    results[file] = result.stdout or result.stderr
                    logger.warning(f"Formatting issues found in {file}")
                else:
                    logger.info(f"File {file} is properly formatted")

            except Exception as e:
                formatting_failed = True
                results[file] = str(e)
                logger.error(f"Error checking format for {file}: {str(e)}")

        return (not formatting_failed), results

    def get_changed_files(self) -> List[str]:
        """
        Get list of changed Terraform files in the current commit.
        Handles both diff against previous commit and scanning all files.
        """
        try:
            changed_files = []

            try:
                # Try to get the current commit
                head_commit = self.repo.head.commit

                # Get the parent commit if it exists
                if head_commit.parents:
                    parent_commit = head_commit.parents[0]

                    # Get the diff between current and parent commit
                    diffs = parent_commit.diff(head_commit)

                    # Filter for Terraform files
                    for diff in diffs:
                        file_path = diff.a_path or diff.b_path
                        if file_path and (file_path.endswith('.tf') or file_path.endswith('.tf.json')):
                            if Path(file_path).exists():
                                changed_files.append(file_path)

            except (GitCommandError, AttributeError):
                # If diff fails, scan all Terraform files
                logger.info("Falling back to scanning all Terraform files")
                changed_files = [
                                    str(p) for p in Path().rglob('*.tf')
                                ] + [
                                    str(p) for p in Path().rglob('*.tf.json')
                                ]

            return changed_files

        except Exception as e:
            logger.error(f"Error getting changed files: {str(e)}")
            return []


    def post_github_comment(self, results: dict) -> bool:
        """
        Post formatting results as a comment on the GitHub PR.

        Args:
            results: Dictionary of file paths and their formatting issues

        Returns:
            bool: True if comment posted successfully, False otherwise
        """
        if not self.github_token:
            logger.info("No GitHub token provided, skipping comment")
            return True

        try:
            # Get PR number from environment
            event_path = os.getenv('GITHUB_EVENT_PATH')
            if not event_path:
                logger.info("No GitHub event data found, skipping comment")
                return True

            with open(event_path) as f:
                event_data = json.load(f)

            pr_number = event_data.get('pull_request', {}).get('number')
            repo_full_name = event_data.get('repository', {}).get('full_name')

            if not pr_number or not repo_full_name:
                logger.info("Not a pull request, skipping comment")
                return True

            # Create comment body
            if results:
                comment_body = ":x: **Formatting errors found in the following files:**\n\n"
                for file, diff in results.items():
                    comment_body += f"{file}\n```\n{diff}\n```\n\n"
            else:
                comment_body = ":white_check_mark: All Terraform files are properly formatted."

            # Post comment
            repo = self.gh_client.get_repo(repo_full_name)
            pr = repo.get_pull(pr_number)
            pr.create_issue_comment(comment_body)

            return True

        except Exception as e:
            logger.error(f"Failed to post GitHub comment: {str(e)}")
            return False

    @staticmethod
    def _is_valid_version(version: str) -> bool:
        """Validate Terraform version string format."""
        import re
        return bool(re.match(r'^\d+\.\d+\.\d+$', version))


def main():
    """Main entry point for the script."""
    # Get required environment variables
    terraform_version = os.getenv('INPUT_TERRAFORM_VERSION')
    github_token = os.getenv('GITHUB_TOKEN')

    if not terraform_version:
        logger.error("No Terraform version specified")
        sys.exit(1)

    # Initialize formatter
    formatter = TerraformFormatter(terraform_version, github_token)

    # Run pre-flight checks
    if not formatter.validate_inputs():
        logger.error("Pre-flight validation failed")
        sys.exit(1)

    # Set up Terraform
    if not formatter.setup_terraform():
        logger.error("Failed to set up Terraform")
        sys.exit(1)

    # Get changed files
    changed_files = formatter.get_changed_files()
    if not changed_files:
        logger.info("No Terraform files to check")
        sys.exit(0)

    # Check formatting
    success, results = formatter.check_formatting(changed_files)

    # Post results to GitHub if applicable
    if not formatter.post_github_comment(results):
        logger.error("Failed to post GitHub comment")
        sys.exit(1)

    # Exit with appropriate status
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
