#!/usr/bin/env python3
"""Send one 28x28 MNIST image through UART to PicoRV32 + CNN."""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

import serial


READY_PREFIX = "READY 784"
RESULT_RE = re.compile(
    r"RESULT CLASS=(?P<class>\d+) CYCLES=(?P<cycles>\d+) "
    r"FRAME=(?P<frame>\d+) STATUS=0x(?P<status>[0-9A-Fa-f]+)"
)


def load_mem_image(path: Path, image_index: int) -> bytes:
    tokens = path.read_text(encoding="ascii").split()
    start = image_index * 784
    end = start + 784
    if end > len(tokens):
        raise ValueError(
            f"{path} has {len(tokens)} pixels; image {image_index} needs {end}"
        )
    values = bytes(int(token, 16) for token in tokens[start:end])
    if len(values) != 784:
        raise AssertionError("internal image length error")
    return values


def read_line(port: serial.Serial, deadline: float) -> str:
    while time.monotonic() < deadline:
        raw = port.readline()
        if raw:
            return raw.decode("ascii", errors="replace").strip()
    raise TimeoutError("UART line timeout")


def wait_ready(port: serial.Serial, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while True:
        line = read_line(port, deadline)
        if line:
            print(f"FPGA: {line}")
        if line.startswith(READY_PREFIX):
            return


def run_one(
    port: serial.Serial, image: bytes, timeout: float
) -> tuple[int, int, int, int]:
    port.write(image)
    port.flush()

    deadline = time.monotonic() + timeout
    while True:
        line = read_line(port, deadline)
        if line:
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


def main() -> int:
    default_vector = Path(__file__).resolve().parents[1] / "data" / "mnist_vector0.mem"
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True, help="for example COM3")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--input", type=Path, default=default_vector)
    parser.add_argument("--index", type=int, default=0)
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--expected", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--no-reset-prompt",
        action="store_true",
        help="do not pause to ask for KEY[0] reset",
    )
    args = parser.parse_args()

    image = load_mem_image(args.input, args.index)
    checksum_sum = sum(image) & 0xFFFFFFFF
    checksum_xor = 0
    for value in image:
        checksum_xor ^= value

    print(f"Pixels: {len(image)}")
    print(f"SUM   : 0x{checksum_sum:08X}")
    print(f"XOR   : 0x{checksum_xor:02X}")

    with serial.Serial(args.port, args.baud, timeout=0.2) as port:
        port.reset_input_buffer()
        port.reset_output_buffer()

        if not args.no_reset_prompt:
            input("Press KEY[0] for about 0.2 s, release it, then press Enter...")

        passed = 0
        last_cycles: int | None = None

        for run in range(1, args.repeat + 1):
            wait_ready(port, args.timeout)
            result, cycles, frame, status = run_one(port, image, args.timeout)
            class_ok = result == args.expected
            cycle_ok = last_cycles is None or cycles == last_cycles
            passed += int(class_ok and cycle_ok)

            print(
                f"RUN {run}: class={result} expected={args.expected} "
                f"cycles={cycles} frame={frame} status=0x{status:08X} "
                f"=> {'PASS' if class_ok and cycle_ok else 'FAIL'}"
            )
            last_cycles = cycles

    print(f"FINAL: {passed}/{args.repeat} repeat tests passed")
    return 0 if passed == args.repeat else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TimeoutError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(2)
