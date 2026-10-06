"""Unit tests for the broker's pure helpers. Run with mitmproxy's Python:

    "$(dirname "$(readlink -f "$(mise which mitmdump)")")/python" -m unittest \
        tools/crates/pi-safe/broker/broker_test.py
"""

import base64
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

import broker


class GithubOrg(unittest.TestCase):
    def test_api_paths(self):
        self.assertEqual(
            broker.github_org("api.github.com", "/repos/ASG-SONG/app/pulls?state=open"),
            "ASG-SONG",
        )
        self.assertEqual(
            broker.github_org("api.github.com", "/orgs/oneaudi/repos"), "oneaudi"
        )
        self.assertEqual(
            broker.github_org("uploads.github.com", "/repos/a/b/releases/1/assets"), "a"
        )
        self.assertIsNone(broker.github_org("api.github.com", "/user"))
        self.assertIsNone(broker.github_org("api.github.com", "/repos"))

    def test_search_qualifiers(self):
        path = "/search/issues?q=is%3Apr+repo%3AASG-SONG%2Fapp+author%3Ame"
        self.assertEqual(broker.github_org("api.github.com", path), "ASG-SONG")
        self.assertIsNone(broker.github_org("api.github.com", "/search/code?q=foo"))

    def test_graphql(self):
        body = json.dumps(
            {
                "query": "query($owner:String!){...}",
                "variables": {"owner": "ASG-SONG", "repo": "x"},
            }
        )
        self.assertEqual(
            broker.github_org("api.github.com", "/graphql", body.encode()), "ASG-SONG"
        )
        body = json.dumps(
            {"query": 'query { repository(owner: "oneaudi", name: "x") { id } }'}
        )
        self.assertEqual(
            broker.github_org("api.github.com", "/graphql", body.encode()), "oneaudi"
        )
        body = json.dumps({"query": "q", "variables": {"q": "repo:abc/def is:open"}})
        self.assertEqual(
            broker.github_org("api.github.com", "/graphql", body.encode()), "abc"
        )
        self.assertIsNone(broker.github_org("api.github.com", "/graphql", b"{"))
        self.assertIsNone(
            broker.github_org(
                "api.github.com", "/graphql", b'{"query":"{ viewer { login } }"}'
            )
        )

    def test_github_com_and_raw(self):
        self.assertEqual(
            broker.github_org(
                "github.com", "/ASG-SONG/app.git/info/refs?service=git-upload-pack"
            ),
            "ASG-SONG",
        )
        self.assertIsNone(broker.github_org("github.com", "/login/oauth/access_token"))
        self.assertEqual(
            broker.github_org("raw.githubusercontent.com", "/org/repo/main/README.md"),
            "org",
        )


class PickKey(unittest.TestCase):
    keys = frozenset({"ASG-SONG", "default"})

    def test_org_wins_case_insensitively(self):
        self.assertEqual(broker.pick_key("asg-song", "other", self.keys), "ASG-SONG")

    def test_org_without_token_is_default_not_hint(self):
        self.assertEqual(broker.pick_key("torvalds", "ASG-SONG", self.keys), "default")

    def test_hint_when_request_names_no_org(self):
        self.assertEqual(broker.pick_key(None, "ASG-SONG", self.keys), "ASG-SONG")
        self.assertEqual(broker.pick_key(None, "arielschiavoni", self.keys), "default")
        self.assertEqual(broker.pick_key(None, None, self.keys), "default")


class Misc(unittest.TestCase):
    def test_proxy_user(self):
        header = "Basic " + base64.b64encode(b"ASG-SONG:pi-safe").decode()
        self.assertEqual(broker.proxy_user(header), "ASG-SONG")
        self.assertIsNone(broker.proxy_user("Bearer x"))
        self.assertIsNone(broker.proxy_user(""))

    def test_path_matches(self):
        self.assertTrue(broker.path_matches("/jira/rest/api/2/myself", "/jira/"))
        self.assertTrue(broker.path_matches("/jira", "/jira/"))
        self.assertFalse(broker.path_matches("/jiralike", "/jira/"))
        self.assertTrue(broker.path_matches("/anything", "/"))

    def test_shipped_rules_parse(self):
        rules = Path(__file__).parents[4] / "config/pi-safe/.config/pi-safe/broker.toml"
        r = broker.Rules.load(rules)
        self.assertEqual(r.github_hosts["api.github.com"], "bearer")
        self.assertTrue(any(b.path == "/copilot_internal/v2/token" for b in r.blocks))
        self.assertEqual(
            r.oauth_token_command[:3], ["pi", "auth", "print-bearer-token"]
        )


class PiLoginsToken(unittest.TestCase):
    """pi is replaced by `echo`, which prints the "refreshed" token."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.auth = Path(self.dir.name) / "auth.json"
        self.logins = broker.PiLogins(self.auth)
        self.pi = ["echo", "fresh-{provider}"]

    def tearDown(self):
        self.dir.cleanup()

    def login(self, minutes_left):
        expires = int(time.time() * 1000) + minutes_left * 60_000
        entry = {
            "type": "oauth",
            "refresh": "r",
            "access": "stored",
            "expires": expires,
        }
        self.auth.write_text(json.dumps({"github-copilot": entry}))

    def test_valid_token_comes_from_auth_json_without_pi(self):
        self.login(60)
        self.assertEqual(self.logins.token("github-copilot", ["false"]), "stored")

    def test_expiring_token_is_refreshed_by_pi(self):
        self.login(2)
        self.assertEqual(
            self.logins.token("github-copilot", self.pi), "fresh-github-copilot"
        )

    def test_no_login_asks_pi_which_reports_it(self):
        self.auth.write_text("{}")
        self.assertEqual(self.logins.token("anthropic", self.pi), "fresh-anthropic")
        with self.assertRaisesRegex(RuntimeError, "exited 1: not logged in"):
            self.logins.token(
                "anthropic", ["sh", "-c", "echo not logged in >&2; exit 1"]
            )

    def test_missing_command(self):
        self.auth.write_text("{}")
        with self.assertRaisesRegex(LookupError, "no command configured"):
            self.logins.token("anthropic", [])

    def test_copilot_github_token_is_the_login_refresh_token(self):
        self.login(2)  # expiry is irrelevant: the GitHub token does not expire
        self.assertEqual(self.logins.copilot_github_token(), "r")
        self.auth.write_text("{}")
        with self.assertRaisesRegex(LookupError, "no github-copilot login"):
            self.logins.copilot_github_token()


if __name__ == "__main__":
    unittest.main()
