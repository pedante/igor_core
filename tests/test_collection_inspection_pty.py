"""Real System selection/READ/details/Back through the existing curses session."""

from test_ai_tui_collection_backend import (
    test_system_curses_pagination_refresh_loading_and_session_preservation as exercise,
)


def test_system_read_inspection_and_back(tmp_path):
    exercise(tmp_path, inspect=True)
