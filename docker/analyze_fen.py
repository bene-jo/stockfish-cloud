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
    hashfull: int | None


@dataclass
class EngineMetadata:
    name: str | None
    version: str | None
    eval_file: str | None
    nnue: bool


@dataclass
class StabilitySample:
    depth: int
    move_prefixes: list[list[str]]
    pv_lengths: list[int]
    scores: list[int]
    nodes: int | None
    hashfull: int | None


@dataclass
class StabilityResult:
    state: str
    reason: str
    complete_depth: int | None = None
    sample_count: int = 0
    depth_span: int = 0
    nodes: int | None = None
    hashfull: int | None = None


class StabilityTracker:
    minimum_settling_depth = 30
    minimum_stable_depth = 40
    minimum_settling_nodes = 75_000_000
    minimum_stable_nodes = 150_000_000
    minimum_pv_moves = 8
    compared_prefix_moves = 6
    settling_sample_count = 4
    stable_sample_count = 8
    settling_depth_span = 3
    stable_depth_span = 6
    settling_score_windows = [15, 25, 25, 30, 30]
    stable_score_windows = [8, 12, 12, 15, 15]
    hashfull_warning_threshold = 900

    def __init__(self, fen: str, expected_line_count: int) -> None:
        self.fen = fen
        self.expected_line_count = expected_line_count
        self.lines_by_depth: dict[int, dict[int, EngineLine]] = {}
        self.sampled_depths: set[int] = set()
        self.samples: list[StabilitySample] = []
        self.result = StabilityResult(
            state="unstable",
            reason=f"Waiting for {expected_line_count} complete lines.",
        )

    def update(self, line: EngineLine) -> StabilityResult:
        if line.depth is None or line.multipv > self.expected_line_count:
            return self.result

        depth_lines = self.lines_by_depth.setdefault(line.depth, {})
        depth_lines[line.multipv] = line

        if len(depth_lines) < self.expected_line_count:
            self.result = StabilityResult(
                state="unstable",
                reason=(
                    f"Waiting for all {self.expected_line_count} lines at depth "
                    f"{line.depth}."
                ),
                complete_depth=self.complete_depth,
                sample_count=len(self.samples),
                depth_span=self.depth_span,
                nodes=self.latest_nodes,
                hashfull=self.latest_hashfull,
            )
            return self.result

        if line.depth not in self.sampled_depths:
            self.sampled_depths.add(line.depth)
            self.samples.append(self.sample_from_depth(line.depth, depth_lines))

        self.result = self.evaluate()
        return self.result

    @property
    def complete_depth(self) -> int | None:
        if not self.samples:
            return None
        return self.samples[-1].depth

    @property
    def depth_span(self) -> int:
        if len(self.samples) < 2:
            return 0
        return self.samples[-1].depth - self.samples[0].depth

    @property
    def latest_nodes(self) -> int | None:
        if not self.samples:
            return None
        return self.samples[-1].nodes

    @property
    def latest_hashfull(self) -> int | None:
        if not self.samples:
            return None
        return self.samples[-1].hashfull

    def sample_from_depth(
        self,
        depth: int,
        depth_lines: dict[int, EngineLine],
    ) -> StabilitySample:
        lines = [depth_lines[index] for index in range(1, self.expected_line_count + 1)]
        nodes_values = [line.nodes for line in lines if line.nodes is not None]
        hashfull_values = [line.hashfull for line in lines if line.hashfull is not None]
        return StabilitySample(
            depth=depth,
            move_prefixes=[
                line.pv[: self.compared_prefix_moves]
                for line in lines
            ],
            pv_lengths=[len(line.pv) for line in lines],
            scores=[
                score_for_white(self.fen, line.score)
                for line in lines
                if line.score is not None
            ],
            nodes=max(nodes_values) if nodes_values else None,
            hashfull=max(hashfull_values) if hashfull_values else None,
        )

    def evaluate(self) -> StabilityResult:
        if not self.samples:
            return self.result

        latest = self.samples[-1]
        base = {
            "complete_depth": latest.depth,
            "sample_count": len(self.samples),
            "depth_span": self.depth_span,
            "nodes": latest.nodes,
            "hashfull": latest.hashfull,
        }

        short_line = self.short_line(latest)
        if short_line:
            return StabilityResult(
                state="unstable",
                reason=short_line,
                **base,
            )

        if latest.hashfull is not None and latest.hashfull >= self.hashfull_warning_threshold:
            return StabilityResult(
                state="unstable",
                reason=(
                    f"Hash is {latest.hashfull / 10:.1f}% full; increase hash "
                    "before trusting stability."
                ),
                **base,
            )

        stable_failure = self.failure_reason(
            minimum_depth=self.minimum_stable_depth,
            minimum_nodes=self.minimum_stable_nodes,
            required_samples=self.stable_sample_count,
            required_depth_span=self.stable_depth_span,
            score_windows=self.stable_score_windows,
            label="stable",
        )
        if stable_failure is None:
            return StabilityResult(
                state="stable",
                reason="All displayed lines converged across the stable evidence window.",
                **base,
            )

        settling_failure = self.failure_reason(
            minimum_depth=self.minimum_settling_depth,
            minimum_nodes=self.minimum_settling_nodes,
            required_samples=self.settling_sample_count,
            required_depth_span=self.settling_depth_span,
            score_windows=self.settling_score_windows,
            label="settling",
        )
        if settling_failure is None:
            return StabilityResult(
                state="settling",
                reason="Displayed lines are consistent, but stable evidence is not complete yet.",
                **base,
            )

        return StabilityResult(
            state="unstable",
            reason=stable_failure,
            **base,
        )

    def short_line(self, sample: StabilitySample) -> str | None:
        for index, pv_length in enumerate(sample.pv_lengths, start=1):
            if pv_length < self.minimum_pv_moves:
                return (
                    f"Line {index} only has {pv_length} moves; "
                    f"stable needs {self.minimum_pv_moves}."
                )
        if len(sample.scores) < self.expected_line_count:
            return "Waiting for scores on all displayed lines."
        return None

    def failure_reason(
        self,
        minimum_depth: int,
        minimum_nodes: int,
        required_samples: int,
        required_depth_span: int,
        score_windows: list[int],
        label: str,
    ) -> str | None:
        latest = self.samples[-1]
        if latest.depth < minimum_depth:
            return f"Depth {latest.depth}; {label} needs depth {minimum_depth}+."

        if latest.nodes is None:
            return "Waiting for searched node count."

        if latest.nodes < minimum_nodes:
            return (
                f"Searched {latest.nodes:,} nodes; {label} needs "
                f"{minimum_nodes:,}."
            )

        if len(self.samples) < required_samples:
            return (
                f"Collected {len(self.samples)} complete depth samples; "
                f"{label} needs {required_samples}."
            )

        recent = self.samples[-required_samples:]
        depth_span = recent[-1].depth - recent[0].depth
        if depth_span < required_depth_span:
            return (
                f"Evidence spans {depth_span} depths; {label} needs "
                f"{required_depth_span}."
            )

        prefix_reason = self.prefix_change_reason(recent)
        if prefix_reason:
            return prefix_reason

        score_reason = self.score_drift_reason(recent, score_windows, label)
        if score_reason:
            return score_reason

        return None

    def prefix_change_reason(self, samples: list[StabilitySample]) -> str | None:
        reference = samples[0].move_prefixes
        for sample in samples[1:]:
            for index, prefix in enumerate(sample.move_prefixes, start=1):
                if index > len(reference) or prefix != reference[index - 1]:
                    return (
                        f"Line {index} PV changed within the evidence window."
                    )
        return None

    def score_drift_reason(
        self,
        samples: list[StabilitySample],
        score_windows: list[int],
        label: str,
    ) -> str | None:
        for line_index in range(self.expected_line_count):
            if any(len(sample.scores) <= line_index for sample in samples):
                return "Waiting for scores on all displayed lines."

            scores = [sample.scores[line_index] for sample in samples]
            drift = max(scores) - min(scores)
            window = score_windows[min(line_index, len(score_windows) - 1)]
            if drift > window:
                return (
                    f"Line {line_index + 1} eval drift is {drift / 100:.2f}; "
                    f"{label} allows {window / 100:.2f}."
                )
        return None

    def to_dict(self) -> dict:
        return {
            "state": self.result.state,
            "reason": self.result.reason,
            "completeDepth": self.result.complete_depth,
            "sampleCount": self.result.sample_count,
            "depthSpan": self.result.depth_span,
            "nodes": self.result.nodes,
            "hashfull": self.result.hashfull,
        }


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
    hashfull = int_after("hashfull")

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
        hashfull=hashfull,
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
        "hashfull": line.hashfull,
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
    stability_tracker: StabilityTracker,
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
        "stability": stability_tracker.to_dict(),
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
        stability_tracker = StabilityTracker(args.fen, args.multipv)
        stable_stop_requested = False
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
                stability = stability_tracker.update(parsed)
                if args.stream:
                    emit_jsonl(
                        analysis_state(
                            args,
                            started_at,
                            latest_lines,
                            engine_metadata,
                            stability_tracker,
                            status="running",
                            updated_line=parsed,
                        )
                    )
                if stability.state == "stable" and not stable_stop_requested:
                    send(process, "stop")
                    stable_stop_requested = True

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
            "stability": stability_tracker.to_dict(),
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
                    stability_tracker,
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
