"""
AWS CLI credential cache helper.

Finds the remaining valid time for IAM role credentials in ~/.aws/cli/cache/,
matching by role_arn (for source_profile chains) or sso_role_name (for direct SSO profiles).

Usage:
    python3 aws_session_remaining.py <role_arn> <sso_role_name>

Prints remaining time as "<Xh Ym>" if a valid credential is found, nothing otherwise.
"""

import json
import os
import glob
import sys
from datetime import datetime, timezone


def find_remaining(role_arn: str, sso_role_name: str) -> str | None:
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
            # Pick the credential with the most time remaining
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
    result = find_remaining(role_arn, sso_role_name)
    if result:
        print(result)
