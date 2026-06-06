#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass


@dataclass
class EngineLine:
    multipv: int
    depth: int | None
    score_type: str | None
    score: int | None
    pv: list[str]
    nodes: int | None
    nps: int | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze one FEN with Stockfish.")
    parser.add_argument("--stockfish", required=True)
    parser.add_argument("--fen", required=True)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--hash", type=int, default=256)
    parser.add_argument("--multipv", type=int, default=1)
    parser.add_argument("--depth", type=int)
    parser.add_argument("--movetime", type=int)
    parser.add_argument(
        "--stream",
        action="store_true",
        help="Emit live analysis updates as JSONL instead of one final JSON document.",
    )
    return parser.parse_args()


def send(process: subprocess.Popen[str], command: str) -> None:
    assert process.stdin is not None
    process.stdin.write(command + "\n")
    process.stdin.flush()


def read_until(process: subprocess.Popen[str], marker: str) -> list[str]:
    assert process.stdout is not None
    lines: list[str] = []
    while True:
        line = process.stdout.readline()
        if line == "":
            raise RuntimeError(f"Stockfish exited before {marker}")
        line = line.rstrip("\n")
        lines.append(line)
        if line == marker:
            return lines


def parse_info(line: str) -> EngineLine | None:
    if not line.startswith("info "):
        return None

    tokens = line.split()
    if "pv" not in tokens:
        return None

    def int_after(name: str) -> int | None:
        if name not in tokens:
            return None
        index = tokens.index(name)
        if index + 1 >= len(tokens):
            return None
        try:
            return int(tokens[index + 1])
        except ValueError:
            return None

    multipv = int_after("multipv") or 1
    depth = int_after("depth")
    nodes = int_after("nodes")
    nps = int_after("nps")

    score_type = None
    score = None
    if "score" in tokens:
        score_index = tokens.index("score")
        if score_index + 2 < len(tokens):
            score_type = tokens[score_index + 1]
            try:
                score = int(tokens[score_index + 2])
            except ValueError:
                score = None

    pv_index = tokens.index("pv")
    pv = tokens[pv_index + 1 :]

    return EngineLine(
        multipv=multipv,
        depth=depth,
        score_type=score_type,
        score=score,
        pv=pv,
        nodes=nodes,
        nps=nps,
    )


def parse_bestmove(line: str) -> tuple[str | None, str | None]:
    match = re.match(r"bestmove\s+(\S+)(?:\s+ponder\s+(\S+))?", line)
    if not match:
        return None, None
    bestmove = None if match.group(1) == "(none)" else match.group(1)
    return bestmove, match.group(2)


def engine_line_to_dict(line: EngineLine) -> dict:
    return {
        "multipv": line.multipv,
        "depth": line.depth,
        "scoreType": line.score_type,
        "score": line.score,
        "pv": line.pv,
        "nodes": line.nodes,
        "nps": line.nps,
    }


def sorted_engine_lines(lines: dict[int, EngineLine]) -> list[dict]:
    return [
        engine_line_to_dict(line)
        for line in sorted(lines.values(), key=lambda item: item.multipv)
    ]


def parameters_to_dict(args: argparse.Namespace) -> dict:
    return {
        "threads": args.threads,
        "hashMb": args.hash,
        "multipv": args.multipv,
        "depth": args.depth,
        "movetimeMs": args.movetime,
    }


def analysis_state(
    args: argparse.Namespace,
    started_at: float,
    latest_lines: dict[int, EngineLine],
    status: str,
    bestmove: str | None = None,
    ponder: str | None = None,
    updated_line: EngineLine | None = None,
) -> dict:
    state = {
        "event": "analysis_state",
        "status": status,
        "fen": args.fen,
        "elapsedMs": round((time.time() - started_at) * 1000),
        "parameters": parameters_to_dict(args),
        "bestmove": bestmove,
        "ponder": ponder,
        "lines": sorted_engine_lines(latest_lines),
    }
    if updated_line:
        state["updatedLine"] = engine_line_to_dict(updated_line)
    return state


def emit_jsonl(event: dict) -> None:
    print(json.dumps(event, separators=(",", ":")), flush=True)


def main() -> int:
    args = parse_args()
    if not args.depth and not args.movetime:
        args.movetime = 10_000

    started_at = time.time()
    process = subprocess.Popen(
        [args.stockfish],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    try:
        send(process, "uci")
        read_until(process, "uciok")
        send(process, f"setoption name Threads value {args.threads}")
        send(process, f"setoption name Hash value {args.hash}")
        send(process, f"setoption name MultiPV value {args.multipv}")
        send(process, "isready")
        read_until(process, "readyok")
        send(process, f"position fen {args.fen}")
        if args.depth:
            send(process, f"go depth {args.depth}")
        else:
            send(process, f"go movetime {args.movetime}")

        latest_lines: dict[int, EngineLine] = {}
        raw: list[str] = []
        bestmove = None
        ponder = None
        assert process.stdout is not None
        while True:
            line = process.stdout.readline()
            if line == "":
                raise RuntimeError("Stockfish exited before bestmove")
            line = line.rstrip("\n")
            raw.append(line)

            parsed = parse_info(line)
            if parsed:
                latest_lines[parsed.multipv] = parsed
                if args.stream:
                    emit_jsonl(
                        analysis_state(
                            args,
                            started_at,
                            latest_lines,
                            status="running",
                            updated_line=parsed,
                        )
                    )

            if line.startswith("bestmove"):
                bestmove, ponder = parse_bestmove(line)
                break

        send(process, "quit")
        process.wait(timeout=5)

        result = {
            "fen": args.fen,
            "bestmove": bestmove,
            "ponder": ponder,
            "elapsedMs": round((time.time() - started_at) * 1000),
            "parameters": parameters_to_dict(args),
            "lines": sorted_engine_lines(latest_lines),
            "raw": raw,
        }
        if args.stream:
            emit_jsonl(
                analysis_state(
                    args,
                    started_at,
                    latest_lines,
                    status="completed",
                    bestmove=bestmove,
                    ponder=ponder,
                )
            )
        else:
            print(json.dumps(result, indent=2))
        return 0
    finally:
        if process.poll() is None:
            process.kill()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
