#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import time


def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        print(f"Error executing command {' '.join(cmd)}: {exc.stderr.strip()}", file=sys.stderr)
        return None
    return res.stdout.strip()


def get_run(run_id, repo):
    out = run_cmd(["gh", "run", "view", str(run_id), "--repo", repo, "--json", "status,conclusion,headSha,displayTitle"])
    if not out:
        return None
    try:
        return json.loads(out)
    except Exception as exc:
        print(f"Failed to parse JSON for run {run_id}: {exc}", file=sys.stderr)
        return None


def find_publish_run(head_sha, repo):
    out = run_cmd(["gh", "run", "list", "--repo", repo, "--workflow", "publish.yml", "--json", "databaseId,headSha,status,conclusion"])
    if not out:
        return None
    try:
        runs = json.loads(out)
    except Exception as exc:
        print(f"Failed to parse publish runs list: {exc}", file=sys.stderr)
        return None

    for run in runs:
        if run.get("headSha") == head_sha:
            return run.get("databaseId")
    return None


def monitor_run(run_id, repo, label, poll_interval, retry_interval=30):
    while True:
        run = get_run(run_id, repo)
        if not run:
            print(f"Warning: failed to retrieve {label} run {run_id}; retrying in {retry_interval}s...")
            time.sleep(retry_interval)
            continue

        status = run.get("status")
        conclusion = run.get("conclusion")
        title = run.get("displayTitle") or ""
        print(f"{label} run {run_id}: {status} | conclusion={conclusion} | {title}")

        if status == "completed":
            if conclusion == "success":
                return run
            print(f"{label} run {run_id} completed with non-success conclusion: {conclusion}")
            raise SystemExit(1)

        time.sleep(poll_interval)


def main():
    parser = argparse.ArgumentParser(description="Watch a GitHub Actions build run and its follow-on publish run")
    parser.add_argument("build_run_id", nargs="?", help="GitHub Actions build run ID")
    parser.add_argument("--build-run-id", dest="build_run_id_opt", help="GitHub Actions build run ID")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "projectbluefin/dakota"), help="GitHub repository in owner/name form")
    parser.add_argument("--poll-interval", type=int, default=45, help="Seconds between run-status polls")
    parser.add_argument("--publish-poll-interval", type=int, default=15, help="Seconds between publish-run discovery attempts")
    args = parser.parse_args()

    build_run_id = args.build_run_id_opt or args.build_run_id or os.environ.get("BUILD_RUN_ID")
    if not build_run_id:
        parser.error("build_run_id is required (pass it as an argument or set BUILD_RUN_ID)")

    print(f"Starting GHA pipeline monitoring for {args.repo}")
    print(f"Monitoring build run: {build_run_id}")

    build_run = monitor_run(build_run_id, args.repo, "build", args.poll_interval)
    head_sha = build_run.get("headSha")
    if not head_sha:
        raise SystemExit("Could not resolve head SHA for build run. Exiting.")

    print(f"Build run succeeded. Waiting for publish run to start for SHA {head_sha}...")

    publish_run_id = None
    for _ in range(10):
        publish_run_id = find_publish_run(head_sha, args.repo)
        if publish_run_id:
            print(f"Found publish run: {publish_run_id}")
            break
        print(f"Publish run not found yet; checking again in {args.publish_poll_interval}s...")
        time.sleep(args.publish_poll_interval)

    if not publish_run_id:
        raise SystemExit("Timed out waiting for a publish run to be triggered.")

    monitor_run(publish_run_id, args.repo, "publish", args.poll_interval)
    print("Publish run completed successfully.")


if __name__ == "__main__":
    main()
