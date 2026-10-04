"""One swayidle instance, two power profiles; no direct suspend or unlock.

UPower is polled every five seconds. Changing power source re-arms the idle
timers and restores monitor power. A failed power query selects short privacy
timeouts but never automatic suspend. swayidle handles Wayland and logind idle
inhibitors (including Noctalia caffeine); sleep-only inhibitors affect suspend,
not screen locking. Noctalia owns the logind lock-before-sleep handshake.
"""

import json
import os
import shlex
import signal
import subprocess
import sys
import threading


PROFILES = {
    "ac": (900, 1200, None),
    "battery": (300, 360, 1200),
    "unknown": (300, 360, None),
}
POLL_SECONDS = 5
COMMAND_TIMEOUT = 5


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
        # Unlike lock-and-suspend, plain lock fails if the user disabled the
        # locker in the GUI. Do not let upstream's disabled-locker fallback
        # turn an automatic suspend into an unlocked suspend.
        run("noctalia", "msg", "session", "lock")
        # With no usable outputs upstream may defer the lock and immediately
        # execute its post-lock callback. Refuse that path for idle suspend.
        # `locked` here includes an active lock request; the native callback
        # below still waits for the compositor's acknowledgment in that case.
        status = json.loads(run("noctalia", "msg", "status"))
        if not isinstance(status, dict) or status.get("locked") is not True:
            raise ValueError("No active Noctalia lock; automatic suspend cancelled")
        # Noctalia waits for the compositor's locked event, then invokes the
        # systemctl backend configured in noctalia-idle.nix. Never plain sleep.
        run("noctalia", "msg", "session", "lock-and-suspend")
    elif name == "lock":
        run("noctalia", "msg", "session", "lock")
    elif name == "screen-off":
        # Retry locking if the earlier timeout met a transient IPC failure.
        # A failed request leaves the display on, rather than masking failure.
        run("noctalia", "msg", "session", "lock")
        run("noctalia", "msg", "dpms-off")
    elif name == "screen-on":
        run("noctalia", "msg", "dpms-on")
    else:
        raise ValueError(f"Unknown action: {name}")


def swayidle_command(profile):
    lock, screen, suspend = PROFILES[profile]

    def command(name):
        return shlex.join([sys.executable, os.path.realpath(__file__), name])

    args = [
        "swayidle", "-w",
        "timeout", str(lock), command("lock"),
        "timeout", str(screen), command("screen-off"),
        "resume", command("screen-on"),
    ]
    if suspend is not None:
        args.extend(["timeout", str(suspend), command("suspend")])
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
        # Expected if Noctalia already stopped at logout; never hide the
        # original supervisor failure or leave its child process alive.
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
        raise ValueError("Usage: noctalia-idle [lock|screen-off|screen-on|suspend]")


if __name__ == "__main__":
    try:
        main()
    except (subprocess.SubprocessError, OSError, ValueError, RuntimeError, AttributeError) as error:
        print(f"noctalia-idle: {error}", file=sys.stderr)
        sys.exit(1)
