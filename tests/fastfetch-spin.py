"""Tests for the spinning fastfetch player, in a pseudo-terminal.

The player is the real built wrapper, but around a fake fastfetch: info
lines are fixed and any other invocation prints "REAL <args>". A minimal
terminal emulator replays the output to check what stays on the screen.
"""

import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time

(binary, frames_dir, stty, width, height, count,
 pad_top, pad_left, pad_right) = sys.argv[1:]
width, height, count = int(width), int(height), int(count)
pad_top, pad_left, pad_right = int(pad_top), int(pad_left), int(pad_right)
frames_dir = Path(frames_dir)

SGR = re.compile(r"\x1b\[[0-9;]*m")
INFO = [f"info line {i:02d}" for i in range(1, 25)]
ROWS = max(len(INFO), pad_top + height)
UP = f"\x1b[{ROWS - pad_top}A"

lines = frames_dir.joinpath("frames.txt").read_text().splitlines()
frames = [lines[k * height:(k + 1) * height] for k in range(count)]
schedule = [int(k) for k in frames_dir.joinpath("schedule.txt").read_text().split()]


def visible(line):
    return SGR.sub("", line)


class Screen:
    """Just the sequences the player emits; anything else is a failure."""

    def __init__(self, rows, cols):
        self.rows, self.cols = rows, cols
        self.lines = [[" "] * cols for _ in range(rows)]
        self.row = self.col = 0
        self.wrap = True

    def feed(self, text):
        for token in re.findall(r"\x1b\[[0-9;?]*[A-Za-z]|.", text, re.S):
            if token.startswith("\x1b"):
                self.csi(token)
            elif token == "\r":
                self.col = 0
            elif token == "\n":   # the pty turns it into CR LF (onlcr)
                self.col = 0
                self.row += 1
                if self.row == self.rows:
                    self.lines = self.lines[1:] + [[" "] * self.cols]
                    self.row -= 1
            else:
                if self.col >= self.cols:
                    if not self.wrap:
                        continue
                    self.col = 0
                    self.feed("\n")
                self.lines[self.row][self.col] = token
                self.col += 1

    def csi(self, token):
        body, final = token[2:-1], token[-1]
        if final == "m":
            return
        if token[2:] in ("?7l", "?7h"):
            self.wrap = final == "h"
            return
        if token[2:] in ("?25l", "?25h"):
            return
        n = int(body or 1)
        if final == "A":
            self.row = max(0, self.row - n)
        elif final == "B":
            self.row = min(self.rows - 1, self.row + n)
        elif final == "G":
            self.col = n - 1
        else:
            raise AssertionError(f"unexpected sequence {token!r}")

    def text(self):
        return ["".join(line).rstrip() for line in self.lines]


def expected(frame, cols):
    out = []
    for r in range(ROWS):
        i = r - pad_top
        logo = visible(frames[frame][i]) if 0 <= i < height else " " * width
        info = INFO[r] if r < len(INFO) else ""
        out.append((" " * pad_left + logo + " " * pad_right + info)[:cols].rstrip())
    return out


def run_pty(args=(), env=None, rows=50, cols=120, send=None):
    """Run under a pty; `send` = (seconds, bytes) typed during the run."""
    environment = {"PATH": os.environ["PATH"], "TERM": "xterm-256color"}
    environment.update(env or {})
    # stty -g before and after: the player must restore the terminal modes.
    script = (f'printf "BEFORE %s\\n" "$({stty} -g)"; "$@"; status=$?; '
              f'printf "AFTER %s\\n" "$({stty} -g)"; exit $status')
    command = ["sh", "-c", script, "sh", binary, *args]
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.execvpe(command[0], command, environment)
    output, start, sent = b"", time.monotonic(), False
    while True:
        if send and not sent and time.monotonic() - start >= send[0]:
            os.write(fd, send[1])
            sent = True
        ready, _, _ = select.select([fd], [], [], 0.05)
        if time.monotonic() - start > 30:
            raise AssertionError("player did not finish")
        if not ready:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        output += chunk
    _, status = os.waitpid(pid, 0)
    os.close(fd)
    elapsed = time.monotonic() - start
    match = re.fullmatch(r"BEFORE (\S+)\r\n(.*)AFTER (\S+)\r\n", output.decode(), re.S)
    assert match, output
    before, body, after = match.groups()
    assert before == after, "terminal modes not restored"
    return os.waitstatus_to_exitcode(status), body, elapsed


def screen_after(body, rows=50, cols=120):
    screen = Screen(rows, cols)
    screen.feed(body.replace("\r\n", "\n"))
    return screen.text()[:ROWS]


def same(got, want):
    """Screen comparison with a readable diff on failure."""
    if got != want:
        import difflib
        diff = difflib.unified_diff(want, got, "expected", "screen", lineterm="")
        raise AssertionError("\n" + "\n".join(diff))


def check_frames():
    assert len(lines) == count * height
    for line in lines:
        assert len(visible(line)) == width, repr(visible(line))
    assert frames_dir.joinpath("logo.txt").read_text().splitlines() == frames[0]
    assert len(schedule) == 90 and schedule[-1] == 0
    assert all(0 <= k < count for k in schedule)

    def filled(frame):
        return sum(c != " " for line in frame for c in visible(line))

    # Facing front the snowflake fills the frame; edge-on it is a thin strip.
    assert filled(frames[count // 4]) * 4 < filled(frames[0])
    assert len({tuple(frame) for frame in frames}) == count
    colours = set(re.findall(r"\x1b\[38;2;([0-9;]+)m", "".join(frames[0])))
    assert len(colours) >= 4, colours


def check_passthrough():
    code, body, _ = run_pty(["--version"])
    assert (code, body) == (0, "REAL --version\r\n"), body
    for env in ({"FASTFETCH_SPIN": "off"}, {"TERM": "dumb"}):
        code, body, _ = run_pty(env=env)
        assert (code, body) == (0, "REAL \r\n"), (env, body)
    piped = subprocess.run([binary], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, check=True)
    assert piped.stdout == "REAL \n", piped.stdout


def check_animation():
    code, body, _ = run_pty()
    assert code == 0
    assert body.startswith("\x1b[?7l\x1b[?25l")
    assert body.endswith("\x1b[?25h\x1b[?7h")
    # One redraw per remaining tick, plus the final front-facing frame.
    assert body.count(UP) == len(schedule), body.count(UP)
    same(screen_after(body), expected(0, 120))


def check_key_skips():
    code, body, elapsed = run_pty(send=(0.5, b"\x1b[A"))
    assert code == 0 and elapsed < 2.5, elapsed
    assert body.count(UP) < len(schedule)
    same(screen_after(body), expected(0, 120))

    code, body, _ = run_pty(env={"FASTFETCH_SPIN": "loop"}, send=(0.7, b"q"))
    assert code == 0 and body.count(UP) > 3
    same(screen_after(body), expected(0, 120))


def check_interrupt():
    code, body, _ = run_pty(send=(0.5, b"\x03"))
    assert code == 130, code
    same(screen_after(body), expected(0, 120))


def check_small_terminal():
    code, body, _ = run_pty(rows=ROWS)
    assert code == 0 and UP not in body and "\x1b[?25l" not in body
    same(screen_after(body, rows=ROWS + 2), expected(0, 120))
    # Narrow: lines are cut, not wrapped, so the rows still line up.
    code, body, _ = run_pty(cols=60)
    assert code == 0
    same(screen_after(body, cols=60), expected(0, 60))


check_frames()
check_passthrough()
check_animation()
check_key_skips()
check_interrupt()
check_small_terminal()
print("fastfetch-spin: ok")
