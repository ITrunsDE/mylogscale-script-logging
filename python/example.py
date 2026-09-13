#!/usr/bin/env python3
import argparse
from pathlib import Path

from logscale import initialize_logscale, write_logscale

_HERE = Path(__file__).resolve().parent


def main() -> None:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument(
        "config_path",
        nargs="?",
        default=str(_HERE / "logscale.json"),
        help="Path to logscale.json",
    )
    args = parser.parse_args()
    script_name = Path(__file__).stem
    logger = initialize_logscale(args.config_path, script_name)

    write_logscale(logger, "INFO", "Script started", {"job": "demo"})
    # Replace this harmless operation with your existing work. Keep its error handling unchanged.
    result = 6 * 7
    write_logscale(logger, "INFO", "Calculation completed", {"result": result})
    write_logscale(logger, "WARN", "Demonstration warning")
    write_logscale(logger, "ERROR", "Demonstration error event; no operation failed")
    write_logscale(logger, "INFO", "Script completed")
    print(f"Main script result: {result}")


if __name__ == "__main__":
    main()
