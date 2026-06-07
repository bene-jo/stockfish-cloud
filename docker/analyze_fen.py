#!/usr/bin/env python3
import argparse
import json
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass

import chess

ACTIVE_PROCESS: subprocess.Popen[str] | None = None
STOP_REQUESTED = False


@dataclass
class EngineLine:
    multipv: int
    depth: int | None
    score_type: str | None
    score: int | None
    pv: list[str]
    nodes: int | None
    nps: int | None


@dataclass
class EngineMetadata:
    name: str | None
    version: str | None
    eval_file: str | None
    nnue: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze one FEN with Stockfish.")
    parser.add_argument("--stockfish", required=True)
    parser.add_argument("--fen", required=True)
    parser.add_argument("--threads", type=int, default=1)
    parser.add_argument("--hash", type=int, default=256)
    parser.add_argument("--multipv", type=int, default=1)
    parser.add_argument("--depth", type=int)
    parser.add_argument("--movetime", type=int)
    parser.add_argument("--position-id")
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


def request_stop(signum: int, frame: object) -> None:
    del signum, frame

    global STOP_REQUESTED
    STOP_REQUESTED = True
    if ACTIVE_PROCESS and ACTIVE_PROCESS.poll() is None:
        try:
            send(ACTIVE_PROCESS, "stop")
        except Exception:
            pass


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


def parse_engine_metadata(uci_lines: list[str]) -> EngineMetadata:
    name = None
    eval_file = None

    for line in uci_lines:
        if line.startswith("id name "):
            name = line.removeprefix("id name ").strip()
        elif line.startswith("Stockfish "):
            name = line.strip()
        elif line.startswith("option name EvalFile "):
            match = re.search(r"\bdefault\s+(\S+)", line)
            if match:
                eval_file = match.group(1)

    version = None
    if name:
        match = re.search(r"\bStockfish\s+(\S+)", name)
        if match:
            version = match.group(1)

    return EngineMetadata(
        name=name,
        version=version,
        eval_file=eval_file,
        nnue=bool(eval_file),
    )


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


def score_for_white(fen: str, score: int | None) -> int | None:
    if score is None:
        return None

    board = chess.Board(fen)
    if board.turn == chess.BLACK:
        return -score

    return score


def san_pv_for_fen(fen: str, pv: list[str]) -> list[str]:
    board = chess.Board(fen)
    san_moves: list[str] = []

    for move_text in pv:
        try:
            move = chess.Move.from_uci(move_text)
        except ValueError:
            break

        if move not in board.legal_moves:
            break

        prefix = ""
        if board.turn == chess.WHITE:
            prefix = f"{board.fullmove_number}."
        elif not san_moves:
            prefix = f"{board.fullmove_number}..."

        san = board.san(move)
        san_moves.append(f"{prefix} {san}" if prefix else san)
        board.push(move)

    return san_moves


def engine_metadata_to_dict(metadata: EngineMetadata) -> dict:
    return {
        "name": metadata.name,
        "version": metadata.version,
        "evalFile": metadata.eval_file,
        "nnue": metadata.nnue,
    }


def engine_line_to_dict(line: EngineLine, fen: str) -> dict:
    return {
        "multipv": line.multipv,
        "depth": line.depth,
        "scoreType": line.score_type,
        "score": score_for_white(fen, line.score),
        "rawScore": line.score,
        "pv": line.pv,
        "san": san_pv_for_fen(fen, line.pv),
        "nodes": line.nodes,
        "nps": line.nps,
    }


def sorted_engine_lines(lines: dict[int, EngineLine], fen: str) -> list[dict]:
    return [
        engine_line_to_dict(line, fen)
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
    engine_metadata: EngineMetadata,
    status: str,
    bestmove: str | None = None,
    ponder: str | None = None,
    updated_line: EngineLine | None = None,
) -> dict:
    current_depth = max(
        (line.depth for line in latest_lines.values() if line.depth is not None),
        default=None,
    )
    state = {
        "event": "analysis_state",
        "positionId": args.position_id,
        "status": status,
        "fen": args.fen,
        "elapsedMs": round((time.time() - started_at) * 1000),
        "currentDepth": current_depth,
        "targetDepth": args.depth,
        "parameters": parameters_to_dict(args),
        "engine": engine_metadata_to_dict(engine_metadata),
        "bestmove": bestmove,
        "ponder": ponder,
        "lines": sorted_engine_lines(latest_lines, args.fen),
    }
    if updated_line:
        state["updatedLine"] = engine_line_to_dict(updated_line, args.fen)
    return state


def emit_jsonl(event: dict) -> None:
    print(json.dumps(event, separators=(",", ":")), flush=True)


def main() -> int:
    global ACTIVE_PROCESS

    args = parse_args()
    if not args.depth and not args.movetime:
        args.movetime = 10_000

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    started_at = time.time()
    process = subprocess.Popen(
        [args.stockfish],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    ACTIVE_PROCESS = process

    try:
        send(process, "uci")
        uci_lines = read_until(process, "uciok")
        engine_metadata = parse_engine_metadata(uci_lines)
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
                            engine_metadata,
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
            "positionId": args.position_id,
            "status": "completed",
            "parameters": parameters_to_dict(args),
            "currentDepth": max(
                (line.depth for line in latest_lines.values() if line.depth is not None),
                default=None,
            ),
            "targetDepth": args.depth,
            "engine": engine_metadata_to_dict(engine_metadata),
            "lines": sorted_engine_lines(latest_lines, args.fen),
            "raw": raw,
        }
        if args.stream:
            emit_jsonl(
                analysis_state(
                    args,
                    started_at,
                    latest_lines,
                    engine_metadata,
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
        ACTIVE_PROCESS = None


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        raise SystemExit(1)
