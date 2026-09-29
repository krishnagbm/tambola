import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'functions'))

from send_email import _is_public_game_visible


def test_visible_public_game_is_allowed():
    assert _is_public_game_visible({
        'status': 'COMPLETED',
        'is_private': False,
        'is_publicly_visible': True,
    }) is True


def test_cancelled_game_is_hidden():
    assert _is_public_game_visible({
        'status': 'CANCELLED',
        'is_private': False,
        'is_publicly_visible': True,
    }) is False


def test_private_game_is_hidden():
    assert _is_public_game_visible({
        'status': 'COMPLETED',
        'is_private': True,
        'is_publicly_visible': True,
    }) is False


def test_admin_hidden_game_is_hidden():
    assert _is_public_game_visible({
        'status': 'COMPLETED',
        'is_private': False,
        'is_publicly_visible': False,
    }) is False
