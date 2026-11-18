#!/usr/bin/env python3
"""Install a Volta benchmark APK and gate four-player FPS on an ADB device."""

import argparse
import re
import subprocess
import sys
import threading
from pathlib import Path
from queue import Empty, Queue


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--serial", help="ADB device serial")
    parser.add_argument("--min-fps", type=float, default=29.5)
    parser.add_argument("--max-p95-ms", type=float, default=50)
    args = parser.parse_args()
    if not args.apk.is_file():
        parser.error(f"APK not found: {args.apk}")

    adb = ["adb", "-s", args.serial] if args.serial else ["adb"]
    package = "com.homegame.volta"
    subprocess.run([*adb, "get-state"], check=True)
    subprocess.run([*adb, "install", "-r", str(args.apk)], check=True)
    subprocess.run([*adb, "shell", "am", "force-stop", package], check=True)
    subprocess.run(
        [*adb, "shell", "am", "start", "-W", "-n", f"{package}/.MainActivity"],
        check=True,
        timeout=30,
    )
    pid = subprocess.check_output(
        [*adb, "shell", "pidof", "-s", package], text=True, timeout=10,
    ).strip()
    result = Queue()
    with subprocess.Popen(
        [*adb, "logcat", "--pid", pid, "-T", "1", "-s", "flutter"],
        stdout=subprocess.PIPE,
        text=True,
    ) as log:
        def read_result():
            for line in log.stdout:
                match = re.search(
                    r"VOLTA_BENCHMARK_RESULT fps=([\d.]+) p95_ms=([\d.]+) views=4 "
                    r"ui_p95_ms=([\d.]+) raster_p95_ms=([\d.]+)",
                    line,
                )
                if match:
                    result.put(tuple(map(float, match.groups())))
                    return
            result.put(None)

        threading.Thread(target=read_result, daemon=True).start()
        try:
            metrics = result.get(timeout=115)
            if metrics is None:
                raise RuntimeError("ADB stopped before the benchmark finished")
        except Empty as error:
            raise RuntimeError("No result. Use an APK built with VOLTA_BENCHMARK=true.") from error
        finally:
            log.terminate()

    fps, p95, ui, raster = metrics
    passed = fps >= args.min_fps and p95 <= args.max_p95_ms
    print(
        f"{'PASS' if passed else 'FAIL'} | 4 players | {fps:.2f} FPS | "
        f"frame p95 {p95:.2f} ms | UI p95 {ui:.2f} ms | raster p95 {raster:.2f} ms"
    )
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
