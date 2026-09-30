import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'functions'))

from recent_games import _is_public_game_visible


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


def test_completed_game_with_zero_winners_is_visible():
    # A completed game with 0 winners is NOT cancelled and should be visible if not private/hidden
    assert _is_public_game_visible({
        'status': 'COMPLETED',
        'is_private': False,
        'is_publicly_visible': True,
        'winners_roster': [],
    }) is True


def test_in_progress_and_draft_games_are_hidden():
    for st in ['DRAFT', 'OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS']:
        assert _is_public_game_visible({
            'status': st,
            'is_private': False,
            'is_publicly_visible': True,
        }) is False
