import sys
from pathlib import Path
import time
import hashlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'functions'))

from dvaa_brand_approval import (
    _clean_domain,
    _make_verification_token,
    _verify_token,
    BLOCKED_FREE_DOMAINS,
)


def test_clean_domain():
    assert _clean_domain("https://pocketbull.net") == "pocketbull.net"
    assert _clean_domain("http://www.nike.com/store") == "nike.com"
    assert _clean_domain("STARBUCKS.COM") == "starbucks.com"
    assert _clean_domain("sub.company.co.uk:8080/path") == "sub.company.co.uk"


def test_blocked_free_domains():
    assert "gmail.com" in BLOCKED_FREE_DOMAINS
    assert "yahoo.com" in BLOCKED_FREE_DOMAINS
    assert "pocketbull.net" not in BLOCKED_FREE_DOMAINS


def test_make_and_verify_token():
    email = "helpdesk@pocketbull.net"
    domain = "pocketbull.net"
    token = _make_verification_token(email, domain)
    assert token is not None
    assert _verify_token(token, email, domain) is True

    # Tampered email should fail
    assert _verify_token(token, "attacker@other.com", domain) is False
    # Tampered domain should fail
    assert _verify_token(token, email, "otherdomain.com") is False
    # Tampered token should fail
    assert _verify_token(token + "bad", email, domain) is False

