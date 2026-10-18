"""One swayidle instance, two power profiles; locking always goes through hyprlock.

UPower is polled every five seconds. Changing power source re-arms the idle
timers and restores monitor power. A failed power query selects short privacy
timeouts but never automatic suspend. swayidle handles Wayland and logind idle
inhibitors; sleep-only inhibitors affect suspend, not screen locking.

hyprlock runs as its own user service (hyprlock.service, home/lock.nix), so
restarting this supervisor can never kill an active lock screen. A lock only
counts once hyprlock logs that the compositor confirmed it ("onLockLocked"):
suspend, screen-off and before-sleep all wait for that, and give up instead
of sleeping or blanking an unlocked session.
"""

import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import threading
import time


PROFILES = {
    "ac": (900, 1200, None),
    "battery": (300, 360, 1200),
    "unknown": (300, 360, None),
}
POLL_SECONDS = 5
COMMAND_TIMEOUT = 5
# logind waits at most 5 s (InhibitDelayMaxSec) for before-sleep handlers.
LOCK_TIMEOUT = 4
LOCKED_LINE = "onLockLocked called"
LOCK_SERVICE = "hyprlock.service"


def run(*args):
    return subprocess.run(
        args, check=True, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=COMMAND_TIMEOUT,
    ).stdout


def property_value(service, path, interface, name, kind):
    reply = json.loads(run(
        "busctl", "--system", "--json=short", "get-property",
        service, path, interface, name,
    ))
    value = reply.get("data")
    expected = {"b": bool, "s": str}[kind]
    if reply.get("type") != kind or type(value) is not expected:
        raise ValueError(f"Invalid {name} response")
    return value


def power_profile():
    try:
        battery = property_value(
            "org.freedesktop.UPower", "/org/freedesktop/UPower",
            "org.freedesktop.UPower", "OnBattery", "b",
        )
        return "battery" if battery else "ac"
    except (subprocess.SubprocessError, OSError, ValueError, AttributeError):
        return "unknown"


def lock_log():
    return Path(os.environ["XDG_RUNTIME_DIR"]) / "hyprlock.log"


def lock_active():
    try:
        run("systemctl", "--user", "--quiet", "is-active", LOCK_SERVICE)
        return True
    except subprocess.CalledProcessError:
        return False


def lock():
    """Start hyprlock if needed and wait until the compositor has locked."""
    log = lock_log()
    if not lock_active():
        # A stale log from the previous lock must not confirm this one.
        log.unlink(missing_ok=True)
        run("systemctl", "--user", "start", LOCK_SERVICE)
    deadline = time.monotonic() + LOCK_TIMEOUT
    while time.monotonic() < deadline:
        try:
            if LOCKED_LINE in log.read_text(errors="replace"):
                return
        except FileNotFoundError:
            pass
        if not lock_active():
            raise RuntimeError("hyprlock exited before locking")
        time.sleep(0.05)
    raise RuntimeError("hyprlock did not confirm the lock in time")


def action(name):
    if name == "suspend":
        # Recheck at execution time: the adapter may have been plugged in
        # before the supervisor's next poll. Unknown state must not sleep.
        if power_profile() != "battery":
            return
        blocked = property_value(
            "org.freedesktop.login1", "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager", "BlockInhibited", "s",
        ).split(":")
        if "sleep" in blocked or "idle" in blocked:
            return
        # Never an unlocked suspend: lock() raises if hyprlock cannot lock.
        lock()
        # The final inhibitor check closes the race with a job started
        # after the BlockInhibited read.
        run("systemctl", "--check-inhibitors=yes", "--no-ask-password", "suspend")
    elif name == "lock":
        lock()
    elif name == "screen-off":
        # Retry locking if the earlier timeout met a transient failure.
        # A failed lock leaves the display on, rather than masking it.
        lock()
        run("wlopm", "--off", "*")
    elif name == "screen-on":
        run("wlopm", "--on", "*")
    else:
        raise ValueError(f"Unknown action: {name}")


def swayidle_command(profile):
    lock_after, screen_after, suspend_after = PROFILES[profile]

    def command(name):
        return shlex.join([sys.executable, os.path.realpath(__file__), name])

    # -w: swayidle holds logind's sleep delay until before-sleep returns,
    # so the machine never sleeps before the lock is confirmed.
    args = [
        "swayidle", "-w",
        "timeout", str(lock_after), command("lock"),
        "timeout", str(screen_after), command("screen-off"),
        "resume", command("screen-on"),
    ]
    if suspend_after is not None:
        args.extend(["timeout", str(suspend_after), command("suspend")])
    args.extend([
        # Mod+L and anything else calling `loginctl lock-session`.
        "lock", command("lock"),
        "before-sleep", command("lock"),
        "after-resume", command("screen-on"),
    ])
    return args


def stop_child(child):
    if child is None:
        return
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=3)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=3)


def restore_display():
    try:
        action("screen-on")
    except (subprocess.SubprocessError, OSError):
        # Expected if the compositor already went away at logout; never hide
        # the original supervisor failure or leave its child process alive.
        pass


def supervise(stop):
    child = None
    profile = None
    try:
        while not stop.is_set():
            next_profile = power_profile()
            if next_profile != profile:
                stop_child(child)
                if child is not None:
                    restore_display()
                child = subprocess.Popen(swayidle_command(next_profile))
                profile = next_profile
                print(f"Idle profile: {profile}", flush=True)
            if child.poll() is not None:
                raise RuntimeError("swayidle exited; restarting the supervisor")
            stop.wait(POLL_SECONDS)
    finally:
        stop_child(child)
        restore_display()


def main():
    if len(sys.argv) == 2:
        action(sys.argv[1])
    elif len(sys.argv) == 1:
        stop = threading.Event()
        for signum in (signal.SIGINT, signal.SIGTERM):
            signal.signal(signum, lambda _signum, _frame: stop.set())
        supervise(stop)
    else:
        raise ValueError("Usage: idle [lock|screen-off|screen-on|suspend]")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.SubprocessError, OSError, ValueError, RuntimeError, AttributeError, KeyError) as error:
        print(f"idle: {error}", file=sys.stderr)
        sys.exit(1)
