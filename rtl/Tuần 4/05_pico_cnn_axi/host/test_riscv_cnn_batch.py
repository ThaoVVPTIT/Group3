#!/usr/bin/env python3
"""Batch-test PicoRV32 + CNN with images and labels from .mem files.

Enhanced display with ANSI colors, Unicode borders, progress bar,
and color-coded confusion matrix for easier result interpretation.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import time
from pathlib import Path

import serial


# ── ANSI Color Helpers ─────────────────────────────────────────────────

def _supports_color() -> bool:
    """Return True when the terminal likely supports ANSI escape codes."""
    if os.environ.get("NO_COLOR"):
        return False
    if os.environ.get("FORCE_COLOR"):
        return True
    if sys.platform == "win32":
        return os.environ.get("TERM") == "xterm" or os.environ.get("WT_SESSION") is not None
    return hasattr(sys.stdout, "isatty") and sys.stdout.isatty()


_COLOR = _supports_color()


def _ansi(code: str) -> str:
    return f"\033[{code}m" if _COLOR else ""


RESET   = _ansi("0")
BOLD    = _ansi("1")
DIM     = _ansi("2")
GREEN   = _ansi("32")
RED     = _ansi("31")
YELLOW  = _ansi("33")
CYAN    = _ansi("36")
MAGENTA = _ansi("35")
WHITE   = _ansi("37")
BG_GREEN  = _ansi("42")
BG_RED    = _ansi("41")
BG_CYAN   = _ansi("46")
BG_YELLOW = _ansi("43")

# Unicode box-drawing characters
BOX_H  = "─"
BOX_V  = "│"
BOX_TL = "┌"
BOX_TR = "┐"
BOX_BL = "└"
BOX_BR = "┘"
BOX_ML = "├"
BOX_MR = "┤"
BOX_MC = "┼"
BOX_MT = "┬"
BOX_MB = "┴"
BAR_FULL  = "█"
BAR_EMPTY = "░"
CHECK = "✓"
CROSS = "✗"
DOT   = "●"


IMAGE_SIZE = 28 * 28
READY_PREFIX = "READY 784"
STATUS_ERROR = 1 << 3
RESULT_RE = re.compile(
    r"RESULT CLASS=(?P<class>\d+) CYCLES=(?P<cycles>\d+) "
    r"FRAME=(?P<frame>\d+) STATUS=0x(?P<status>[0-9A-Fa-f]+)"
)


def load_hex_tokens(path: Path) -> list[int]:
    try:
        tokens = path.read_text(encoding="ascii").split()
    except OSError as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc

    values: list[int] = []
    for index, token in enumerate(tokens):
        try:
            value = int(token, 16)
        except ValueError as exc:
            raise ValueError(
                f"{path}: token {index} is not hexadecimal: {token!r}"
            ) from exc
        if not 0 <= value <= 0xFF:
            raise ValueError(f"{path}: token {index} is outside uint8: {token}")
        values.append(value)
    return values


def load_dataset(
    image_path: Path, label_path: Path
) -> tuple[bytes, list[int], int]:
    pixel_values = load_hex_tokens(image_path)
    labels = load_hex_tokens(label_path)

    if len(pixel_values) % IMAGE_SIZE:
        raise ValueError(
            f"{image_path} has {len(pixel_values)} pixels; "
            f"the count is not divisible by {IMAGE_SIZE}"
        )

    image_count = len(pixel_values) // IMAGE_SIZE
    if len(labels) < image_count:
        raise ValueError(
            f"{label_path} has {len(labels)} labels for {image_count} images"
        )
    if any(label > 9 for label in labels[:image_count]):
        raise ValueError(f"{label_path} contains a label outside class 0..9")

    return bytes(pixel_values), labels, image_count


def image_at(pixels: bytes, image_index: int) -> bytes:
    start = image_index * IMAGE_SIZE
    return pixels[start : start + IMAGE_SIZE]


def image_checksums(image: bytes) -> tuple[int, int]:
    checksum_sum = sum(image) & 0xFFFFFFFF
    checksum_xor = 0
    for value in image:
        checksum_xor ^= value
    return checksum_sum, checksum_xor


def read_line(port: serial.Serial, deadline: float) -> str:
    while time.monotonic() < deadline:
        raw = port.readline()
        if raw:
            return raw.decode("ascii", errors="replace").strip()
    raise TimeoutError("UART line timeout")


def wait_ready(port: serial.Serial, timeout: float, verbose: bool) -> None:
    deadline = time.monotonic() + timeout
    while True:
        line = read_line(port, deadline)
        if verbose and line:
            print(f"FPGA: {line}")
        if line.startswith(READY_PREFIX):
            return
        if line.startswith(("ERROR:", "FATAL:")):
            raise RuntimeError(line)


def run_one(
    port: serial.Serial, image: bytes, timeout: float, verbose: bool
) -> tuple[int, int, int, int]:
    port.write(image)
    port.flush()

    deadline = time.monotonic() + timeout
    while True:
        line = read_line(port, deadline)
        if verbose and line:
            print(f"FPGA: {line}")

        match = RESULT_RE.fullmatch(line)
        if match:
            return (
                int(match.group("class")),
                int(match.group("cycles")),
                int(match.group("frame")),
                int(match.group("status"), 16),
            )

        if line.startswith(("ERROR:", "FATAL:")):
            raise RuntimeError(line)


def _progress_bar(current: int, total: int, width: int = 30) -> str:
    """Return a Unicode progress bar string."""
    filled = int(width * current / total) if total else 0
    return (
        f"{CYAN}{BAR_FULL * filled}{DIM}{BAR_EMPTY * (width - filled)}{RESET}"
        f" {BOLD}{current}{RESET}/{total}"
    )


def _box_line(left: str, fill: str, mid: str, right: str,
              col_widths: list[int]) -> str:
    """Build one horizontal border row of a Unicode table."""
    segments = [fill * w for w in col_widths]
    return left + mid.join(segments) + right


def print_confusion(matrix: list[list[int]]) -> None:
    """Print a color-coded confusion matrix with Unicode borders."""
    n = len(matrix)
    header_label = "true\\pred"
    lw = max(len(header_label), 6) + 2          # left column width
    cw = 5                                       # data column width
    col_widths = [lw] + [cw] * n

    print(f"\n{BOLD}{CYAN}  Confusion Matrix{RESET}")
    print(f"  {DIM}(rows = true label, columns = predicted class){RESET}")

    # top border
    print("  " + _box_line(BOX_TL, BOX_H, BOX_MT, BOX_TR, col_widths))

    # header row
    hdr = f"{BOX_V}{header_label:^{lw}}"
    for c in range(n):
        hdr += f"{BOX_V}{BOLD}{c:^{cw}}{RESET}"
    hdr += BOX_V
    print("  " + hdr)

    # separator
    print("  " + _box_line(BOX_ML, BOX_H, BOX_MC, BOX_MR, col_widths))

    # data rows
    for label, row in enumerate(matrix):
        line = f"{BOX_V}{BOLD}{label:^{lw}}{RESET}"
        for col, val in enumerate(row):
            if val == 0:
                cell = f"{DIM}{'·':^{cw}}{RESET}"
            elif col == label:
                cell = f"{BG_GREEN}{BOLD}{val:^{cw}}{RESET}"   # correct
            else:
                cell = f"{BG_RED}{BOLD}{val:^{cw}}{RESET}"     # misclassified
            line += f"{BOX_V}{cell}"
        line += BOX_V
        print("  " + line)

    # bottom border
    print("  " + _box_line(BOX_BL, BOX_H, BOX_MB, BOX_BR, col_widths))

    # legend
    print(f"  {BG_GREEN} {RESET} Correct   "
          f"{BG_RED} {RESET} Misclassified   "
          f"{DIM}·{RESET} Zero")


def write_csv(path: Path, rows: list[dict[str, int | str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "image_index",
        "true_label",
        "predicted_class",
        "correct",
        "cycles",
        "frame",
        "status_hex",
        "sum_hex",
        "xor_hex",
        "cycle_ok",
        "frame_ok",
        "status_ok",
    ]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _print_banner() -> None:
    """Print a styled startup banner."""
    w = 62
    print(f"\n{BOLD}{CYAN}{'':─^{w}}{RESET}")
    print(f"{BOLD}{CYAN}{DOT} PicoRV32 + CNN  ─  FPGA Batch Test Suite{RESET}")
    print(f"{DIM}{'Hardware accuracy & protocol stability analyzer':^{w}}{RESET}")
    print(f"{BOLD}{CYAN}{'':─^{w}}{RESET}\n")


def _print_config(args: argparse.Namespace, image_count: int, end: int) -> None:
    """Print a configuration summary box."""
    w = 60
    print(f"  {BOX_TL}{BOX_H * w}{BOX_TR}")
    print(f"  {BOX_V}{BOLD}  Configuration{RESET}{' ' * (w - 15)}{BOX_V}")
    print(f"  {BOX_ML}{BOX_H * w}{BOX_MR}")
    items = [
        ("Dataset",  str(args.input)),
        ("Labels",   str(args.labels)),
        ("Port",     str(args.port or "(dry-run)")),
        ("Baud",     str(args.baud)),
        ("Images",   f"{image_count} total"),
        ("Range",    f"{args.start}..{end - 1} ({args.count} images)"),
        ("Exp. Cyc", str(args.expected_cycles)),
    ]
    for key, val in items:
        # Truncate long paths to fit the box
        max_val = w - len(key) - 7
        display_val = val if len(val) <= max_val else "..." + val[-(max_val - 3):]
        padding = w - len(key) - len(display_val) - 5
        print(f"  {BOX_V}  {DIM}{key}{RESET}  {display_val}{' ' * max(0, padding)}{BOX_V}")
    print(f"  {BOX_BL}{BOX_H * w}{BOX_BR}\n")


def main() -> int:
    project_root = Path(__file__).resolve().parents[1]
    default_images = project_root / "data" / "input_1000.mem"
    default_labels = project_root / "data" / "label_1000.mem"
    default_csv = project_root / "reports" / "hardware_batch_results.csv"

    parser = argparse.ArgumentParser(
        description=(
            "Send multiple 28x28 images through UART and measure CNN accuracy "
            "plus RISC-V/MMIO protocol stability."
        )
    )
    parser.add_argument("--port", help="serial port, for example COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--input", type=Path, default=default_images)
    parser.add_argument("--labels", type=Path, default=default_labels)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--expected-cycles",
        type=int,
        default=1282,
        help="use a negative value to disable the exact cycle check",
    )
    parser.add_argument("--csv", type=Path, default=default_csv)
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--no-reset-prompt",
        action="store_true",
        help="do not pause to ask for KEY[0] reset",
    )
    args = parser.parse_args()

    pixels, labels, image_count = load_dataset(args.input, args.labels)
    if args.start < 0:
        parser.error("--start must be non-negative")
    if args.count <= 0:
        parser.error("--count must be positive")
    end = args.start + args.count
    if end > image_count:
        parser.error(
            f"requested images {args.start}..{end - 1}, "
            f"but the dataset contains {image_count} images"
        )

    _print_banner()
    _print_config(args, image_count, end)

    if args.dry_run:
        print("\nDry-run preview:")
        for image_index in range(args.start, min(end, args.start + 10)):
            checksum_sum, checksum_xor = image_checksums(
                image_at(pixels, image_index)
            )
            print(
                f"index={image_index:4d} label={labels[image_index]} "
                f"SUM=0x{checksum_sum:08X} XOR=0x{checksum_xor:02X}"
            )
        return 0

    if not args.port:
        parser.error("--port is required unless --dry-run is used")

    confusion = [[0 for _ in range(10)] for _ in range(10)]
    rows: list[dict[str, int | str]] = []
    correct_count = 0
    protocol_errors = 0
    previous_frame: int | None = None
    observed_cycles: list[int] = []
    started_at = time.monotonic()

    # Table header for per-image results
    hdr_line = (
        f"  {BOLD}{DIM}{'#':>4}  {'Idx':>5}  {'Label':>5}  {'Pred':>5}  "
        f"{'Cycles':>6}  {'Frame':>5}  {'Status':>12}  "
        f"{'Model':>7}  {'Protocol':>10}{RESET}"
    )
    sep_line = f"  {DIM}{'─' * 78}{RESET}"

    with serial.Serial(args.port, args.baud, timeout=0.2) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()

        if not args.no_reset_prompt:
            print(
                f"  {YELLOW}{DOT} Press KEY[0] for ~0.2 s, release it, "
                f"then press Enter...{RESET}"
            )
            input()

        print(f"  {BOLD}{CYAN}{DOT} Running inference...{RESET}\n")
        print(hdr_line)
        print(sep_line)

        for sequence, image_index in enumerate(
            range(args.start, end), start=1
        ):
            image = image_at(pixels, image_index)
            true_label = labels[image_index]
            checksum_sum, checksum_xor = image_checksums(image)

            wait_ready(port, args.timeout, args.verbose)
            prediction, cycles, frame, status = run_one(
                port, image, args.timeout, args.verbose
            )

            correct = prediction == true_label
            cycle_ok = (
                args.expected_cycles < 0 or cycles == args.expected_cycles
            )
            frame_ok = previous_frame is None or frame == previous_frame + 1
            status_ok = (status & STATUS_ERROR) == 0
            protocol_ok = cycle_ok and frame_ok and status_ok

            correct_count += int(correct)
            protocol_errors += int(not protocol_ok)
            confusion[true_label][prediction] += 1
            observed_cycles.append(cycles)

            # Styled per-image line
            model_str = (
                f"{GREEN}{CHECK} OK  {RESET}" if correct
                else f"{RED}{CROSS} MISS{RESET}"
            )
            proto_str = (
                f"{GREEN}{CHECK} OK    {RESET}" if protocol_ok
                else f"{RED}{CROSS} FAIL  {RESET}"
            )
            match_indicator = (
                f"{GREEN}{prediction}{RESET}" if correct
                else f"{RED}{prediction}{RESET}"
            )
            print(
                f"  {sequence:4d}  {image_index:5d}  {true_label:5d}  "
                f"{match_indicator:>5}  {cycles:6d}  {frame:5d}  "
                f"0x{status:08X}    {model_str}  {proto_str}"
            )

            rows.append(
                {
                    "image_index": image_index,
                    "true_label": true_label,
                    "predicted_class": prediction,
                    "correct": int(correct),
                    "cycles": cycles,
                    "frame": frame,
                    "status_hex": f"0x{status:08X}",
                    "sum_hex": f"0x{checksum_sum:08X}",
                    "xor_hex": f"0x{checksum_xor:02X}",
                    "cycle_ok": int(cycle_ok),
                    "frame_ok": int(frame_ok),
                    "status_ok": int(status_ok),
                }
            )
            previous_frame = frame

    elapsed = time.monotonic() - started_at
    accuracy = 100.0 * correct_count / args.count
    miss_count = args.count - correct_count
    avg_cycles = sum(observed_cycles) / len(observed_cycles) if observed_cycles else 0
    throughput = args.count / elapsed if elapsed > 0 else 0

    # ── Summary Dashboard ──────────────────────────────────────────
    print(f"\n  {sep_line}")
    print(f"\n{BOLD}{CYAN}  {'':─^62}{RESET}")
    print(f"{BOLD}{CYAN}  {DOT} Batch Test Summary{RESET}")
    print(f"{BOLD}{CYAN}  {'':─^62}{RESET}\n")

    # Accuracy with progress bar
    acc_color = GREEN if accuracy >= 90 else YELLOW if accuracy >= 70 else RED
    print(f"  {BOLD}Accuracy{RESET}")
    print(f"    {_progress_bar(correct_count, args.count)}")
    print(f"    {acc_color}{BOLD}{accuracy:.2f}%{RESET}  "
          f"({GREEN}{CHECK} {correct_count} correct{RESET}"
          f"  {RED if miss_count else DIM}{CROSS} {miss_count} missed{RESET})\n")

    # Protocol status
    proto_color = GREEN if protocol_errors == 0 else RED
    proto_icon = CHECK if protocol_errors == 0 else CROSS
    print(f"  {BOLD}Protocol{RESET}")
    print(f"    {proto_color}{proto_icon} Errors: {protocol_errors}{RESET}\n")

    # Performance metrics in a mini-table
    print(f"  {BOLD}Performance{RESET}")
    print(f"    {DIM}CNN Cycles{RESET}    min={BOLD}{min(observed_cycles)}{RESET}  "
          f"max={BOLD}{max(observed_cycles)}{RESET}  "
          f"avg={BOLD}{avg_cycles:.0f}{RESET}")
    print(f"    {DIM}Elapsed{RESET}       {BOLD}{elapsed:.2f} s{RESET}")
    print(f"    {DIM}Throughput{RESET}    {BOLD}{throughput:.1f}{RESET} images/sec\n")

    # Confusion Matrix
    print_confusion(confusion)

    # CSV report path
    write_csv(args.csv, rows)
    print(f"\n  {DIM}CSV report saved to:{RESET} {args.csv}")

    # Final verdict banner
    print()
    if protocol_errors:
        print(f"  {BG_RED}{BOLD}  {CROSS} FINAL: HARDWARE/PROTOCOL FAIL  {RESET}")
        return 1

    print(f"  {BG_GREEN}{BOLD}  {CHECK} FINAL: HARDWARE/PROTOCOL PASS  {RESET}")
    print()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TimeoutError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
