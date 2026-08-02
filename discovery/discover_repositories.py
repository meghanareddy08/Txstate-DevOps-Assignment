#!/usr/bin/env python3

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_BASE = "https://api.github.com"

def github_request(url: str, token: str | None = None):
    import time

    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "txstate-devops-assignment",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    if token:
        headers["Authorization"] = f"Bearer {token}"

    retryable_codes = {429, 500, 502, 503, 504}
    max_attempts = 4

    for attempt in range(1, max_attempts + 1):
        request = urllib.request.Request(url, headers=headers)

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))

        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                return None

            if exc.code not in retryable_codes or attempt == max_attempts:
                raise RuntimeError(
                    f"GitHub API request failed: {exc.code} {exc.reason}"
                ) from exc

            retry_after = exc.headers.get("Retry-After")
            delay = int(retry_after) if retry_after else 2 ** (attempt - 1)

            print(
                f"GitHub API returned {exc.code}. "
                f"Retrying in {delay} seconds "
                f"(attempt {attempt}/{max_attempts})...",
                file=sys.stderr,
            )
            time.sleep(delay)

        except urllib.error.URLError as exc:
            if attempt == max_attempts:
                raise RuntimeError(
                    f"GitHub API connection failed: {exc.reason}"
                ) from exc

            delay = 2 ** (attempt - 1)

            print(
                f"GitHub API connection error. "
                f"Retrying in {delay} seconds "
                f"(attempt {attempt}/{max_attempts})...",
                file=sys.stderr,
            )
            time.sleep(delay)

    raise RuntimeError("GitHub API request failed after retries")

def list_repositories(org: str, token: str | None = None):
    repositories = []
    page = 1

    while True:
        url = (
            f"{API_BASE}/orgs/{org}/repos"
            f"?type=all&per_page=100&page={page}"
        )

        data = github_request(url, token)

        if data is None:
            raise RuntimeError(f"Organization '{org}' not found")

        if not data:
            break

        repositories.extend(data)

        if len(data) < 100:
            break

        page += 1

    return repositories


def root_file_exists(
    full_name: str,
    filename: str,
    token: str | None = None,
) -> bool:
    url = f"{API_BASE}/repos/{full_name}/contents/{filename}"
    return github_request(url, token) is not None


def discover(org: str, token: str | None = None):
    inventory = []

    for repo in list_repositories(org, token):
        full_name = repo["full_name"]
        archived = repo.get("archived", False)

        has_dockerfile = root_file_exists(
            full_name,
            "Dockerfile",
            token,
        )

        has_test_sh = root_file_exists(
            full_name,
            "test.sh",
            token,
        )

        inventory.append(
            {
                "name": repo["name"],
                "full_name": full_name,
                "clone_url": repo["clone_url"],
                "default_branch": repo.get("default_branch"),
                "archived": archived,
                "has_dockerfile": has_dockerfile,
                "has_test_sh": has_test_sh,
                "buildable": has_dockerfile and not archived,
            }
        )

    return inventory


def main():
    org = os.getenv("GITHUB_ORG")
    token = os.getenv("GITHUB_TOKEN")

    if not org:
        print("ERROR: GITHUB_ORG is required", file=sys.stderr)
        sys.exit(1)

    output = Path("discovery/repositories.json")
    temp = Path("discovery/repositories.json.tmp")

    try:
        inventory = discover(org, token)

        temp.write_text(
            json.dumps(inventory, indent=2) + "\n",
            encoding="utf-8",
        )

        temp.replace(output)

    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)

        if temp.exists():
            temp.unlink()

        sys.exit(1)

    buildable_count = sum(
        1 for repo in inventory if repo["buildable"]
    )

    print(f"Organization: {org}")
    print(f"Repositories discovered: {len(inventory)}")
    print(f"Buildable repositories: {buildable_count}")
    print(f"Inventory written to: {output}")


if __name__ == "__main__":
    main()
