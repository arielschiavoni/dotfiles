"""
AWS CLI credential cache helper.

Checks two things:
1. SSO token validity in ~/.aws/sso/cache/ (matched by start_url from ~/.aws/config).
2. IAM role credentials remaining time in ~/.aws/cli/cache/ (matched by role_arn or sso_role_name).

Usage:
    python3 aws_session_remaining.py <role_arn> <sso_role_name> <sso_session_name>

Exit codes:
    0 - session valid, prints remaining time as "<Xh Ym> (SSO token: <Xh Ym>)"
    1 - SSO token expired or missing (caller should run `aws sso login`)
    2 - IAM credentials expired/missing but SSO token still valid (stale CLI cache)

Prints a human-readable status line on stdout in all cases.
"""

import configparser
import json
import os
import glob
import sys
from datetime import datetime, timezone


def parse_aws_config() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    cfg.read(os.path.expanduser("~/.aws/config"))
    return cfg


def get_sso_start_url(cfg: configparser.ConfigParser, sso_session_name: str) -> str | None:
    section = f"sso-session {sso_session_name}"
    if cfg.has_section(section):
        return cfg.get(section, "sso_start_url", fallback=None)
    return None


def check_sso_token(start_url: str) -> tuple[bool, str | None]:
    """
    Returns (is_valid, remaining_str).
    Matches the SSO cache file by startUrl.
    """
    cache_dir = os.path.expanduser("~/.aws/sso/cache")
    now = datetime.now(timezone.utc)
    best = None

    for f in glob.glob(os.path.join(cache_dir, "*.json")):
        try:
            data = json.load(open(f))
            if data.get("startUrl") != start_url:
                continue
            exp_str = data.get("expiresAt")
            if not exp_str:
                continue
            exp = datetime.fromisoformat(exp_str.replace("Z", "+00:00"))
            if exp <= now:
                continue
            if best is None or exp > best:
                best = exp
        except Exception:
            pass

    if best is None:
        return False, None

    remaining = best - now
    hours, rem = divmod(int(remaining.total_seconds()), 3600)
    minutes = rem // 60
    return True, f"{hours}h {minutes}m"


def find_iam_remaining(role_arn: str, sso_role_name: str) -> str | None:
    cache_dir = os.path.expanduser("~/.aws/cli/cache")
    now = datetime.now(timezone.utc)
    best = None

    for f in glob.glob(os.path.join(cache_dir, "*.json")):
        try:
            data = json.load(open(f))
            creds = data.get("Credentials", {})
            exp_str = creds.get("Expiration")
            if not exp_str:
                continue
            exp = datetime.fromisoformat(exp_str.replace("Z", "+00:00"))
            if exp <= now:
                continue
            # Match role profiles by role name in AssumedRoleUser.Arn
            if role_arn:
                role_name = role_arn.split("/")[-1]
                arn = data.get("AssumedRoleUser", {}).get("Arn", "")
                if role_name not in arn:
                    continue
            # Match direct SSO profiles by ProviderType
            elif sso_role_name:
                if data.get("ProviderType") != "sso":
                    continue
            if best is None or exp > best:
                best = exp
        except Exception:
            pass

    if best:
        remaining = best - now
        hours, rem = divmod(int(remaining.total_seconds()), 3600)
        minutes = rem // 60
        return f"{hours}h {minutes}m"

    return None


if __name__ == "__main__":
    role_arn = sys.argv[1] if len(sys.argv) > 1 else ""
    sso_role_name = sys.argv[2] if len(sys.argv) > 2 else ""
    sso_session_name = sys.argv[3] if len(sys.argv) > 3 else ""

    cfg = parse_aws_config()

    # --- Check SSO token ---
    sso_valid = True
    sso_remaining = None
    if sso_session_name:
        start_url = get_sso_start_url(cfg, sso_session_name)
        if start_url:
            sso_valid, sso_remaining = check_sso_token(start_url)
        else:
            sso_valid = False

    if not sso_valid:
        print("SSO token expired")
        sys.exit(1)

    # --- Check IAM credentials ---
    iam_remaining = find_iam_remaining(role_arn, sso_role_name)

    if sso_remaining and iam_remaining:
        print(f"{iam_remaining} (SSO token: {sso_remaining})")
    elif sso_remaining:
        print(f"SSO token: {sso_remaining}")
    elif iam_remaining:
        print(iam_remaining)

    sys.exit(0)
