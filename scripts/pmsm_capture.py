"""Receive PMI1 snapshots or decode a recording; never transmit motor commands.

Offline decoding uses only the Python standard library. Live serial needs
pySerial. A board must implement the documented snapshot and timing contract.
"""

import argparse
import csv
import hashlib
import json
import math
import struct
import sys
import time
import zlib
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"PMI1"
FRAME = struct.Struct("<4sBBHIIQ5fI")
FIELDS = ["t", "id", "iq", "ud", "uq", "omega_e", "valid", "saturated", "segment"]


@dataclass(frozen=True)
class Snapshot:
    flags: int
    sequence: int
    run_id: int
    timestamp_us: int
    values: tuple
    discontinuity: bool = False


class Decoder:
    def __init__(self):
        self.buffer = bytearray()
        self.pending_gap = False
        self.crc_errors = 0
        self.header_errors = 0
        self.discarded_bytes = 0

    def discard(self, count):
        del self.buffer[:count]
        self.discarded_bytes += count
        self.pending_gap = True

    def feed(self, data):
        self.buffer.extend(data)
        snapshots = []
        while len(self.buffer) >= 4:
            position = self.buffer.find(MAGIC)
            if position < 0:
                self.discard(len(self.buffer) - 3)
                break
            if position:
                self.discard(position)
            if len(self.buffer) < FRAME.size:
                break
            values = FRAME.unpack_from(self.buffer)
            if values[1] != 1 or values[2] & ~3 or values[3] != FRAME.size:
                self.header_errors += 1
                self.discard(1)
                continue
            if zlib.crc32(self.buffer[:44]) != values[-1]:
                self.crc_errors += 1
                self.discard(1)
                continue
            snapshots.append(Snapshot(values[2], values[4], values[5], values[6],
                                      tuple(values[7:12]), self.pending_gap))
            self.pending_gap = False
            del self.buffer[:FRAME.size]
        return snapshots


def validate_meta(meta):
    if not isinstance(meta, dict):
        raise ValueError("Metadata must be a JSON object.")
    experiment = meta.get("experiment_id")
    if not isinstance(experiment, str) or not experiment.strip() or "replace-" in experiment:
        raise ValueError("Provide a unique, non-placeholder experiment_id.")
    choices = {
        "source_kind": ("measurement", "simulation"),
        "dq_convention": ("amplitude_invariant",),
        "speed_kind": ("electrical",),
        "d_axis": ("pm_flux",),
        "angle_source": ("encoder", "hall_interpolated", "sensorless", "simulation"),
        "voltage_source": ("measured", "reconstructed_compensated", "command", "simulation"),
        "time_alignment": ("verified", "unverified"),
    }
    for key, allowed in choices.items():
        if meta.get(key) not in allowed:
            raise ValueError(f"meta.{key} must be one of {allowed}.")
    units = dict(t="s", id="A", iq="A", ud="V", uq="V", omega_e="rad/s")
    if not isinstance(meta.get("units"), dict) or any(meta["units"].get(k) != v for k, v in units.items()):
        raise ValueError("Convert signals to SI before transmission; unit relabeling is insufficient.")
    if meta["source_kind"] == "measurement" and (
        meta["angle_source"] == "simulation" or meta["voltage_source"] == "simulation"
    ):
        raise ValueError("Measurement metadata cannot declare simulated angle or voltage.")


class CsvWriter:
    def __init__(self, stream):
        self.writer = csv.writer(stream)
        self.writer.writerow(FIELDS)
        self.last = None
        self.first_time = None
        self.segment = 1
        self.rows = 0
        self.missing_sequences = 0
        self.run_id = None

    def append(self, snapshot):
        if self.last is not None:
            if snapshot.run_id != self.last.run_id:
                raise ValueError("run_id changed: keep separate board runs in separate captures.")
            delta = (snapshot.sequence - self.last.sequence) & 0xffffffff
            if delta == 0 or delta >= 0x80000000:
                raise ValueError("Duplicate or backward sequence; do not silently reorder samples.")
            if snapshot.timestamp_us <= self.last.timestamp_us:
                raise ValueError("Sampling clock reset or moved backward.")
            self.missing_sequences += delta - 1
            if delta != 1 or snapshot.discontinuity:
                self.segment += 1
        else:
            self.first_time = snapshot.timestamp_us
            self.run_id = snapshot.run_id
        relative = snapshot.timestamp_us - self.first_time
        if relative >= 2**53:
            raise ValueError("Capture duration exceeds exact microsecond timestamp range.")
        valid = bool(snapshot.flags & 1) and all(math.isfinite(v) for v in snapshot.values)
        self.writer.writerow([relative / 1e6, *snapshot.values, int(valid),
                              int(bool(snapshot.flags & 2)), self.segment])
        self.last = snapshot
        self.rows += 1


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for data in iter(lambda: stream.read(1048576), b""):
            digest.update(data)
    return digest.hexdigest()


def capture_chunks(chunks, meta, output_directory, transport):
    validate_meta(meta)
    folder = Path(output_directory)
    folder.mkdir(parents=True, exist_ok=False)
    decoder = Decoder()
    report = {"schema_version": "1.0", "protocol": "PMI1", "status": "capture_failed",
              "transport": transport, "actuation_commands_sent": 0,
              "bytes": 0, "error": None}
    writer = None
    try:
        (folder / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
        with (folder / "raw.bin").open("xb") as raw, (folder / "samples.csv").open(
            "x", newline="", encoding="utf-8"
        ) as csv_stream:
            writer = CsvWriter(csv_stream)
            for chunk in chunks:
                raw.write(chunk)
                report["bytes"] += len(chunk)
                for sample in decoder.feed(chunk):
                    writer.append(sample)
            if writer.rows < 3:
                raise ValueError("Need at least three verified frames; capture was preserved for diagnosis.")
        report["status"] = "captured"
    except BaseException as error:
        report["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        report.update(crc_errors=decoder.crc_errors, header_errors=decoder.header_errors,
                      discarded_bytes=decoder.discarded_bytes, trailing_bytes=len(decoder.buffer),
                      rows=writer.rows if writer else 0,
                      missing_sequences=writer.missing_sequences if writer else 0,
                      segments=writer.segment if writer else 0,
                      run_id=writer.run_id if writer else None)
        report["sha256"] = {name: file_sha256(folder / name)
                            for name in ("raw.bin", "samples.csv", "meta.json")
                            if (folder / name).is_file()}
        (folder / "capture.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def file_chunks(path):
    with Path(path).open("rb") as stream:
        for data in iter(lambda: stream.read(4096), b""):
            yield data


def serial_chunks(port, baudrate, seconds, max_bytes, dtr, rts):
    try:
        import serial
    except ImportError as error:
        raise RuntimeError("Live reception requires pySerial; offline decode needs no extra package.") from error
    receiver = serial.Serial(port=None, baudrate=baudrate, timeout=min(0.1, seconds),
                             xonxoff=False, rtscts=False, dsrdtr=False)
    # The OS/USB driver can still glitch control lines on open; verify the board.
    receiver.dtr = dtr
    receiver.rts = rts
    receiver.port = port
    try:
        receiver.open()
        deadline = time.monotonic() + seconds
        count = 0
        while time.monotonic() < deadline:
            if count >= max_bytes:
                raise RuntimeError("Capture byte limit reached; partial files retained.")
            chunk = receiver.read(min(4096, max_bytes - count))
            if chunk:
                count += len(chunk)
                yield chunk
    finally:
        receiver.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("decode", "serial"):
        command = commands.add_parser(name)
        command.add_argument("--meta", required=True, type=Path)
        command.add_argument("--output-dir", required=True, type=Path)
        if name == "decode":
            command.add_argument("--input", required=True, type=Path)
        else:
            command.add_argument("--port", required=True)
            command.add_argument("--baud", required=True, type=int)
            command.add_argument("--seconds", required=True, type=float)
            command.add_argument("--max-bytes", type=int, default=16777216)
            command.add_argument("--dtr", required=True, type=int, choices=(0, 1))
            command.add_argument("--rts", required=True, type=int, choices=(0, 1))
    args = parser.parse_args()
    try:
        meta = json.loads(args.meta.read_text(encoding="utf-8-sig"))
        validate_meta(meta)
        if args.command == "decode":
            chunks = file_chunks(args.input)
            transport = {"kind": "file_replay"}
        else:
            if not 0 < args.seconds <= 3600 or args.baud <= 0 or args.max_bytes <= 0:
                raise ValueError("Use a positive baud/byte limit and a finite 0 < seconds <= 3600.")
            chunks = serial_chunks(args.port, args.baud, args.seconds, args.max_bytes,
                                   bool(args.dtr), bool(args.rts))
            transport = {"kind": "serial_receive", "port": args.port, "baudrate": args.baud,
                         "duration_limit_s": args.seconds, "byte_limit": args.max_bytes,
                         "dtr": bool(args.dtr), "rts": bool(args.rts)}
        report = capture_chunks(chunks, meta, args.output_dir, transport)
        print(json.dumps(report, ensure_ascii=False, indent=2))
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Capture rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
