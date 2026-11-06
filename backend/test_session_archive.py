import csv
import json
import tempfile
import unittest
from pathlib import Path

from session_archive import SessionArchive


class SessionArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.archive_path = Path(self.temp_dir.name) / "sessions.json"
        self.config = {
            "api_token": "must-not-be-saved",
            "app_id": "must-not-be-saved",
            "both_random_seed": "must-not-be-saved",
            "symbol": "R_100",
            "account_type": "demo",
            "currency": "USD",
            "contract_type_mode": "BOTH",
            "base_stake": 5.0,
            "max_stake": 1000.0,
            "take_profit": 100.0,
            "stop_loss": 80.0,
            "adaptive_performance_enabled": True,
            "adaptive_target_win_rate": 66.0,
            "adaptive_stop_win_rate": 20.0,
            "adaptive_minimum_sample_size": 30,
            "adaptive_rolling_window": 50,
            "adaptive_stop_loss_enabled": True,
            "adaptive_stop_loss_min_win_rate": 20.0,
            "adaptive_stop_loss_max_win_rate": 66.0,
            "adaptive_stop_loss_rolling_window": 50,
            "under_trigger_digit": 2,
            "over_trigger_digit": 8,
            "win_predict_digit": 8,
            "both_under_barrier": 4,
            "both_over_barrier": 5,
        }
        self.archive = SessionArchive(str(self.archive_path))

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_trade_records_persist_and_update_session_summary(self):
        session_id = self.archive.start_session(self.config, started_at=1000)
        self.assertTrue(self.archive.record_trade(session_id, {
            "contract_id": 123, "placed_at": 1001, "settled_at": 1002,
            "contract_type": "DIGITOVER", "barrier": 5, "entry_signal_digit": 8,
            "generator_digit": 2, "stake": 5.0, "buy_price": 5.0,
            "payout": 9.7, "profit": 4.7, "outcome": "WIN",
            "deriv_status": "won", "entry_spot": "123.45",
            "exit_spot": "123.49", "exit_digit": 9,
        }))
        self.assertFalse(self.archive.record_trade(session_id, {
            "contract_id": 123, "stake": 5, "profit": 4.7, "outcome": "WIN"
        }))
        reloaded = SessionArchive(str(self.archive_path))
        session = reloaded.get_sessions()[0]
        self.assertEqual(session["id"], session_id)
        self.assertEqual(session["summary"]["trade_count"], 1)
        self.assertEqual(session["summary"]["wins"], 1)
        self.assertAlmostEqual(session["summary"]["total_profit"], 4.7)
        self.assertAlmostEqual(session["summary"]["total_stake"], 5.0)
        self.assertEqual(session["trades"][0]["exit_digit"], 9)
        self.assertNotIn("api_token", json.dumps(session))
        self.assertNotIn("both_random_seed", json.dumps(session))
        reloaded.finish_session(session_id, "Stopped by user", finished_at=1100)
        finished = reloaded.get_sessions()[0]
        self.assertEqual(finished["status"], "completed")
        self.assertEqual(finished["finished_at"], 1100)
        self.assertEqual(finished["duration_seconds"], 100)
        self.assertEqual(finished["stop_reason"], "Stopped by user")

    def test_open_trade_is_saved_then_updated_without_double_count(self):
        session_id = self.archive.start_session(self.config, started_at=1000)
        self.assertTrue(self.archive.record_trade_open(session_id, {
            "contract_id": 789,
            "placed_at": 1001,
            "settled_at": None,
            "contract_type": "DIGITOVER",
            "barrier": 5,
            "stake": 6.0,
            "buy_price": 6.0,
            "profit": 0.0,
            "outcome": "OPEN",
            "active_take_profit": 80.0,
            "active_stop_loss": 40.0,
            "rolling_win_rate": 60.0,
            "sl_rolling_win_rate": 55.0,
        }))
        open_session = self.archive.get_sessions()[0]
        self.assertEqual(open_session["summary"]["trade_count"], 1)
        self.assertEqual(open_session["summary"]["wins"], 0)
        self.assertEqual(open_session["trades"][0]["outcome"], "OPEN")

        # A stop event can close the bot session before Deriv sends the
        # final settlement; the original session still receives that result.
        self.archive.finish_session(session_id, "Stopped by user", finished_at=1010)
        self.assertTrue(self.archive.record_trade(session_id, {
            "contract_id": 789,
            "placed_at": 1001,
            "settled_at": 1020,
            "contract_type": "DIGITOVER",
            "barrier": 5,
            "stake": 6.0,
            "buy_price": 6.0,
            "payout": 11.4,
            "profit": 5.4,
            "outcome": "WIN",
            "active_take_profit": 100.0,
            "active_stop_loss": 80.0,
            "rolling_win_rate": 66.0,
            "sl_rolling_win_rate": 70.0,
            "deriv_status": "won",
            "exit_digit": 8,
        }))
        settled_session = self.archive.get_sessions()[0]
        self.assertEqual(settled_session["summary"]["trade_count"], 1)
        self.assertEqual(settled_session["summary"]["wins"], 1)
        self.assertEqual(settled_session["summary"]["losses"], 0)
        self.assertAlmostEqual(settled_session["summary"]["total_stake"], 6.0)
        self.assertAlmostEqual(settled_session["summary"]["total_profit"], 5.4)
        self.assertEqual(settled_session["trades"][0]["outcome"], "WIN")
        # Archived adaptive fields describe the settings used when this
        # contract was opened, not the new rates after its result was added.
        self.assertEqual(settled_session["trades"][0]["active_take_profit"], 80.0)
        self.assertEqual(settled_session["trades"][0]["active_stop_loss"], 40.0)
        self.assertEqual(settled_session["trades"][0]["rolling_win_rate"], 60.0)
        self.assertEqual(settled_session["trades"][0]["sl_rolling_win_rate"], 55.0)
        self.assertFalse(self.archive.record_trade(session_id, {
            "contract_id": 789, "stake": 6.0, "profit": 5.4, "outcome": "WIN"
        }))

    def test_open_sessions_are_recovered_as_interrupted_after_restart(self):
        session_id = self.archive.start_session(self.config, started_at=1000)
        restarted = SessionArchive(str(self.archive_path))
        session = restarted.get_sessions()[0]
        self.assertEqual(session["id"], session_id)
        self.assertEqual(session["status"], "interrupted")
        self.assertIsNotNone(session["finished_at"])
        self.assertIn("Backend restarted", session["stop_reason"])

    def test_csv_export_contains_session_setup_and_trade_results(self):
        session_id = self.archive.start_session(self.config, started_at=1000)
        self.archive.record_trade(session_id, {
            "contract_id": 456, "placed_at": 1001, "settled_at": 1002,
            "contract_type": "DIGITUNDER", "barrier": 4, "stake": 7.5,
            "buy_price": 7.5, "profit": -7.5, "outcome": "LOSS",
            "deriv_status": "lost", "exit_digit": 7,
        })
        rows = list(csv.DictReader(self.archive.export_csv().splitlines()))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["session_id"], session_id)
        self.assertEqual(rows[0]["setup_contract_type_mode"], "BOTH")
        self.assertEqual(rows[0]["trade_contract_type"], "DIGITUNDER")
        self.assertEqual(rows[0]["trade_outcome"], "LOSS")
        self.assertEqual(rows[0]["trade_exit_digit"], "7")

    def test_clear_removes_archived_sessions(self):
        self.archive.start_session(self.config, started_at=1000)
        self.archive.clear()
        self.assertEqual(self.archive.get_sessions(), [])
        self.assertTrue(self.archive_path.exists())


if __name__ == "__main__":
    unittest.main()
