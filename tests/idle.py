"""Regression tests: never contact the real bus, compositor, locker or power manager."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch


sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("idle", sys.argv.pop(1))
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)
hyprlock_source = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else None

ACTIVE = ("systemctl", "--user", "--quiet", "is-active", "hyprlock.service")
START = ("systemctl", "--user", "start", "hyprlock.service")
SUSPEND = ("systemctl", "--check-inhibitors=yes", "--no-ask-password", "suspend")
INACTIVE = subprocess.CalledProcessError(3, "systemctl is-active")


class IdleTests(unittest.TestCase):
    def setUp(self):
        self.runner = patch.object(idle, "run")
        self.run = self.runner.start()
        self.addCleanup(self.runner.stop)
        runtime = tempfile.TemporaryDirectory()
        self.addCleanup(runtime.cleanup)
        self.log = Path(runtime.name) / "hyprlock.log"
        environment = patch.dict(os.environ, {"XDG_RUNTIME_DIR": runtime.name})
        environment.start()
        self.addCleanup(environment.stop)

    def calls(self):
        return [call.args for call in self.run.call_args_list]

    def test_profiles_and_no_sleep_on_ac_or_unknown(self):
        self.assertEqual(idle.PROFILES["ac"], (900, 1200, None))
        self.assertEqual(idle.PROFILES["battery"], (300, 360, 1200))
        self.assertEqual(idle.PROFILES["unknown"], (300, 360, None))
        for profile, timers in idle.PROFILES.items():
            args = idle.swayidle_command(profile)
            self.assertEqual(args[:2], ["swayidle", "-w"])
            self.assertEqual(
                [int(args[i + 1]) for i, word in enumerate(args) if word == "timeout"],
                [timer for timer in timers if timer is not None],
            )
            # Mod+L (loginctl lock-session) and sleep both go through lock().
            events = {args[i]: args[i + 1] for i in range(2, len(args) - 1)
                      if args[i] in ("resume", "lock", "before-sleep", "after-resume")}
            self.assertTrue(events["lock"].endswith(" lock"))
            self.assertTrue(events["before-sleep"].endswith(" lock"))
            self.assertTrue(events["resume"].endswith(" screen-on"))
            self.assertTrue(events["after-resume"].endswith(" screen-on"))
            self.assertNotIn("unlock", args)
            self.assertEqual(any(arg.endswith(" suspend") for arg in args), profile == "battery")

    def test_upower_states_and_fail_closed(self):
        for value, profile in [(True, "battery"), (False, "ac")]:
            self.run.return_value = json.dumps({"type": "b", "data": value})
            self.assertEqual(idle.power_profile(), profile)
        for response in ["bad json", "null", "[]", '{"type":"b","data":"false"}']:
            self.run.return_value = response
            self.assertEqual(idle.power_profile(), "unknown")
        for error in [OSError("bus gone"), subprocess.TimeoutExpired("busctl", 5)]:
            self.run.side_effect = error
            self.assertEqual(idle.power_profile(), "unknown")

    def test_suspend_only_on_battery(self):
        for profile in ["ac", "unknown"]:
            with patch.object(idle, "power_profile", return_value=profile):
                idle.action("suspend")
        self.run.assert_not_called()

    def test_sleep_and_idle_inhibitors_block_only_suspend(self):
        with patch.object(idle, "power_profile", return_value="battery"):
            for blocked in ["sleep", "idle", "handle-power-key:sleep", "idle:sleep"]:
                self.run.return_value = json.dumps({"type": "s", "data": blocked})
                idle.action("suspend")
                self.assertEqual(self.calls()[0][0], "busctl")
                self.assertEqual(self.run.call_count, 1)
                self.run.reset_mock()

    def test_suspend_waits_for_the_confirmed_lock(self):
        self.log.write_text("[LOG] onLockLocked called\n")
        self.run.side_effect = ['{"type":"s","data":"handle-power-key"}', "", ""]
        with patch.object(idle, "power_profile", return_value="battery"):
            idle.action("suspend")
        # Already locked: no second hyprlock, then the checked suspend.
        self.assertEqual(self.calls()[1:], [ACTIVE, SUSPEND])

    def test_failed_lock_never_suspends(self):
        self.run.side_effect = ['{"type":"s","data":""}', INACTIVE, "", INACTIVE]
        with patch.object(idle, "power_profile", return_value="battery"):
            with self.assertRaises(RuntimeError):
                idle.action("suspend")
        self.assertNotIn(SUSPEND, self.calls())
        self.assertIn(START, self.calls())

    def test_inhibitor_failures_never_suspend(self):
        with patch.object(idle, "power_profile", return_value="battery"):
            self.run.side_effect = subprocess.TimeoutExpired("busctl", 5)
            with self.assertRaises(subprocess.TimeoutExpired):
                idle.action("suspend")
            self.assertEqual(self.run.call_count, 1)
            self.run.reset_mock(side_effect=True)
            self.run.return_value = '{"type":"s","data":false}'
            with self.assertRaises(ValueError):
                idle.action("suspend")
            self.assertEqual(self.run.call_count, 1)

    def test_lock_starts_hyprlock_and_ignores_a_stale_log(self):
        self.log.write_text("[LOG] onLockLocked called\n")   # previous lock
        self.run.side_effect = [INACTIVE, "", "", ""]
        started = []

        def sleep(_seconds):
            # The service starts and truncates the log; the compositor
            # confirms on the second poll.
            started.append(True)
            if len(started) == 1:
                self.assertFalse(self.log.exists(), "stale log not removed")
                self.log.write_text("[LOG] locking\n")
            else:
                self.log.write_text("[LOG] locking\n[LOG] onLockLocked called\n")

        with patch.object(idle.time, "sleep", side_effect=sleep):
            idle.lock()
        self.assertEqual(self.calls()[:2], [ACTIVE, START])
        self.assertEqual(len(started), 2)

    def test_lock_fails_when_hyprlock_exits_or_hangs(self):
        self.run.side_effect = [INACTIVE, "", INACTIVE]
        with patch.object(idle.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "exited"):
                idle.lock()
        self.run.reset_mock(side_effect=True)
        self.run.return_value = ""
        clock = iter([0.0, 1.0, 2.0, 3.0, 4.5])
        with patch.object(idle.time, "monotonic", side_effect=lambda: next(clock)), \
                patch.object(idle.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "in time"):
                idle.lock()
        self.assertNotIn(START, self.calls())   # already active: no second locker
        self.assertLess(idle.LOCK_TIMEOUT, 5, "must fit logind's 5 s sleep delay")

    def test_display_off_locks_first_and_failure_stops_sequence(self):
        self.log.write_text("onLockLocked called\n")
        idle.action("screen-off")
        self.assertEqual(self.calls(), [ACTIVE, ("wlopm", "--off", "*")])
        self.run.reset_mock()
        self.run.side_effect = [INACTIVE, subprocess.CalledProcessError(1, "systemctl start")]
        with self.assertRaises(subprocess.CalledProcessError):
            idle.action("screen-off")
        self.assertNotIn(("wlopm", "--off", "*"), self.calls())

    def test_run_has_bounded_timeout_and_no_shell(self):
        # Test the real runner with only subprocess.run mocked.
        self.runner.stop()
        with patch.object(idle.subprocess, "run") as process:
            idle.run("wlopm", "--on", "*")
            self.assertEqual(process.call_args.kwargs["timeout"], 5)
            self.assertTrue(process.call_args.kwargs["check"])
            self.assertNotIn("shell", process.call_args.kwargs)

    def test_supervisor_switches_one_child_and_cleans_up(self):
        stop = MagicMock()
        stop.is_set.side_effect = [False, False, False, True]
        children = [MagicMock(), MagicMock()]
        for child in children:
            child.poll.return_value = None
        with patch.object(idle, "power_profile", side_effect=["ac", "ac", "battery"]), \
                patch.object(idle.subprocess, "Popen", side_effect=children) as launch, \
                patch.object(idle, "stop_child") as terminate, \
                patch.object(idle, "restore_display") as restore:
            events = MagicMock()
            events.attach_mock(launch, "launch")
            events.attach_mock(terminate, "stop")
            idle.supervise(stop)
            self.assertEqual(launch.call_count, 2)
            self.assertEqual(launch.call_args_list[0].args[0], idle.swayidle_command("ac"))
            self.assertEqual(launch.call_args_list[1].args[0], idle.swayidle_command("battery"))
            self.assertEqual([call[0] for call in events.mock_calls], ["stop", "launch", "stop", "launch", "stop"])
            self.assertEqual(terminate.call_args.args, (children[1],))
            self.assertEqual(restore.call_count, 2)
            self.assertEqual(stop.wait.call_count, 3)
            stop.wait.assert_called_with(5)

    def test_crashed_child_raises_for_systemd_restart_and_restores_display(self):
        stop = MagicMock()
        stop.is_set.return_value = False
        child = MagicMock()
        child.poll.return_value = 1
        with patch.object(idle, "power_profile", return_value="ac"), \
                patch.object(idle.subprocess, "Popen", return_value=child), \
                patch.object(idle, "stop_child") as terminate, \
                patch.object(idle, "restore_display") as restore:
            with self.assertRaises(RuntimeError):
                idle.supervise(stop)
            terminate.assert_called_with(child)
            restore.assert_called_once()
            stop.wait.assert_not_called()

    def test_stop_child_terminates_then_kills_only_after_timeout(self):
        child = MagicMock()
        child.poll.return_value = None
        idle.stop_child(child)
        child.terminate.assert_called_once()
        child.wait.assert_called_once_with(timeout=3)
        child.kill.assert_not_called()
        child.reset_mock()
        child.wait.side_effect = [subprocess.TimeoutExpired("swayidle", 3), None]
        idle.stop_child(child)
        child.terminate.assert_called_once()
        child.kill.assert_called_once()
        self.assertEqual(child.wait.call_count, 2)

    def test_resume_never_unlocks_and_bad_action_is_rejected(self):
        idle.action("screen-on")
        self.run.assert_called_once_with("wlopm", "--on", "*")
        with self.assertRaises(ValueError):
            idle.action("unlock")

    @unittest.skipUnless(hyprlock_source, "Source path not supplied")
    def test_upstream_lock_confirmation_contract(self):
        # Upgrade tripwire: the lock handshake reads this exact log line,
        # printed at hyprlock's default verbosity on stdout.
        source = (hyprlock_source / "src" / "core" / "hyprlock.cpp").read_text()
        confirm = source.split("void CHyprlock::onLockLocked() {", 1)[1].split("}", 1)[0]
        self.assertIn(f'Log::logger->log(Log::INFO, "{idle.LOCKED_LINE}");', confirm)
        self.assertIn("m_sLockState.locked = true;", confirm)
        log = (hyprlock_source / "src" / "helpers" / "Log.hpp").read_text()
        self.assertRegex(log, r"\bINFO\s*=\s*Hyprutils::CLI::LOG_DEBUG;")
        self.assertIn("if (level == Hyprutils::CLI::LOG_TRACE && !m_verbose)", log)


unittest.main()
