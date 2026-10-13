"""Protocol/capture behavior tests; no serial ports or motors are opened."""

import csv
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import types
import unittest
from unittest import mock
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import pmsm_capture as capture


def meta():
    return dict(experiment_id="test-run", source_kind="simulation",
                dq_convention="amplitude_invariant", speed_kind="electrical",
                d_axis="pm_flux", angle_source="simulation", voltage_source="simulation",
                time_alignment="verified",
                units=dict(t="s", id="A", iq="A", ud="V", uq="V", omega_e="rad/s"))


def packet(sequence=0, tick=0, run=1, flags=1, values=(1., 2., 3., 4., 5.)):
    body = struct.pack("<4sBBHIIQ5f", b"PMI1", 1, flags, 48, sequence, run, tick, *values)
    return body + struct.pack("<I", zlib.crc32(body))


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("PMSM_SKILL_TMPDIR"))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def decode(self, data):
        return capture.capture_chunks([data], meta(), self.root / "capture", {"kind": "test"})

    def test_arbitrary_chunk_boundaries(self):
        decoder = capture.Decoder()
        result = []
        data = packet(0, 100) + packet(1, 200)
        for byte in data:
            result.extend(decoder.feed(bytes([byte])))
        self.assertEqual([p.timestamp_us for p in result], [100, 200])
        self.assertEqual(decoder.buffer, b"")

    def test_crc_resynchronization_breaks_continuity(self):
        broken = bytearray(packet(1, 200))
        broken[26] ^= 1
        decoder = capture.Decoder()
        result = decoder.feed(packet(0, 100) + broken + packet(2, 300))
        self.assertEqual([p.sequence for p in result], [0, 2])
        self.assertTrue(result[-1].discontinuity)
        self.assertGreaterEqual(decoder.crc_errors, 1)

    def test_garbage_in_stream_makes_boundary(self):
        result = capture.Decoder().feed(packet(0, 100) + b"noise" + packet(1, 200))
        self.assertTrue(result[1].discontinuity)

    def test_unknown_version_and_reserved_flags_rejected(self):
        wrong = bytearray(packet())
        wrong[4] = 2
        decoder = capture.Decoder()
        self.assertEqual(decoder.feed(wrong + packet(flags=4)), [])
        self.assertGreaterEqual(decoder.header_errors, 2)

    def test_partial_tail_not_interpreted_as_a_sample(self):
        decoder = capture.Decoder()
        self.assertEqual(len(decoder.feed(packet() + packet(1, 100)[:23])), 1)
        self.assertEqual(len(decoder.buffer), 23)

    def test_sequence_wrap_is_continuous(self):
        stream = io.StringIO()
        writer = capture.CsvWriter(stream)
        for sample in capture.Decoder().feed(packet(0xffffffff, 100) + packet(0, 200)):
            writer.append(sample)
        self.assertEqual(writer.segment, 1)
        self.assertEqual(writer.missing_sequences, 0)

    def test_lost_sequence_starts_new_segment(self):
        stream = io.StringIO()
        writer = capture.CsvWriter(stream)
        for sample in capture.Decoder().feed(packet(0, 100) + packet(2, 200)):
            writer.append(sample)
        self.assertEqual(writer.segment, 2)
        self.assertEqual(writer.missing_sequences, 1)

    def test_duplicate_and_backward_sequences_rejected(self):
        for following in (4, 3):
            writer = capture.CsvWriter(io.StringIO())
            samples = capture.Decoder().feed(packet(4, 100) + packet(following, 200))
            writer.append(samples[0])
            with self.assertRaisesRegex(ValueError, "Duplicate or backward"):
                writer.append(samples[1])

    def test_run_change_rejected(self):
        samples = capture.Decoder().feed(packet(0, 100) + packet(1, 200, run=2))
        writer = capture.CsvWriter(io.StringIO())
        writer.append(samples[0])
        with self.assertRaisesRegex(ValueError, "run_id changed"):
            writer.append(samples[1])

    def test_clock_reset_rejected(self):
        samples = capture.Decoder().feed(packet(0, 100) + packet(1, 90))
        writer = capture.CsvWriter(io.StringIO())
        writer.append(samples[0])
        with self.assertRaisesRegex(ValueError, "clock reset"):
            writer.append(samples[1])

    def test_invalid_and_saturated_samples_preserved(self):
        self.decode(packet(0, 100, flags=0) + packet(1, 200, flags=3) +
                    packet(2, 300, values=(float("nan"), 2, 3, 4, 5)))
        with (self.root / "capture" / "samples.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual([r["valid"] for r in rows], ["0", "1", "0"])
        self.assertEqual(rows[1]["saturated"], "1")

    def test_relative_time_preserves_large_absolute_ticks(self):
        self.decode(b"".join(packet(k, 2**60 + k * 100) for k in range(3)))
        with (self.root / "capture" / "samples.csv").open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual(float(rows[2]["t"]), 0.0002)

    def test_integrity_hashes_match_saved_files(self):
        report = self.decode(b"".join(packet(k, 100*k) for k in range(3)))
        self.assertEqual(report["status"], "captured")
        for name, digest in report["sha256"].items():
            self.assertEqual(digest, capture.file_sha256(self.root / "capture" / name))

    def test_failure_preserves_raw_and_marks_manifest(self):
        data = packet(0, 100) + packet(0, 200)
        with self.assertRaises(ValueError):
            self.decode(data)
        folder = self.root / "capture"
        self.assertEqual((folder / "raw.bin").read_bytes(), data)
        self.assertEqual(json.loads((folder / "capture.json").read_text())["status"], "capture_failed")

    def test_refuse_existing_output_directory(self):
        folder = self.root / "capture"
        folder.mkdir()
        with self.assertRaises(FileExistsError):
            self.decode(packet())
        self.assertEqual(list(folder.iterdir()), [])

    def test_incomplete_metadata_rejected_before_writes(self):
        invalid = meta()
        invalid["angle_source"] = None
        with self.assertRaises(ValueError):
            capture.capture_chunks([], invalid, self.root / "capture", {})
        self.assertFalse((self.root / "capture").exists())

    def test_mechanical_units_and_fake_provenance_rejected(self):
        invalid = meta()
        invalid["units"]["omega_e"] = "rpm"
        with self.assertRaises(ValueError):
            capture.validate_meta(invalid)
        invalid = meta()
        invalid["source_kind"] = "measurement"
        with self.assertRaises(ValueError):
            capture.validate_meta(invalid)

    def test_c_encoder_agrees_with_python_decoder(self):
        fixture = os.environ.get("PMSM_C_FIXTURE")
        if not fixture:
            self.skipTest("Set PMSM_C_FIXTURE to the compiled C fixture recording.")
        data = Path(fixture).read_bytes()
        result = capture.Decoder().feed(data)
        self.assertEqual(len(result), 3)
        self.assertEqual(result[0].timestamp_us, 4294967297)
        self.assertEqual(result[0].values, (1.25, -2.5, 3.75, -4.5, 123.0))
        self.assertEqual(result[0].flags, 3)
        self.assertEqual([p.sequence for p in result], [0xffffffff, 0, 2])

    def test_serial_receive_is_bounded_and_never_calls_write(self):
        receiver = mock.Mock()
        receiver.read.return_value = b"abc"
        module = types.SimpleNamespace(Serial=mock.Mock(return_value=receiver))
        with mock.patch.dict(sys.modules, {"serial": module}), mock.patch.object(
            capture.time, "monotonic", side_effect=[0., 0., 0.1, 2.]
        ):
            chunks = list(capture.serial_chunks("fake-port", 1000000, 1., 99, False, False))
        self.assertEqual(chunks, [b"abc", b"abc"])
        receiver.write.assert_not_called()
        receiver.open.assert_called_once()
        receiver.close.assert_called_once()
        self.assertFalse(receiver.dtr)
        self.assertFalse(receiver.rts)

    def test_serial_byte_limit_closes_port(self):
        receiver = mock.Mock()
        receiver.read.return_value = b"abc"
        module = types.SimpleNamespace(Serial=lambda **kwargs: receiver)
        with mock.patch.dict(sys.modules, {"serial": module}), mock.patch.object(
            capture.time, "monotonic", return_value=0.
        ):
            with self.assertRaisesRegex(RuntimeError, "byte limit"):
                list(capture.serial_chunks("fake-port", 1000000, 1., 6, False, False))
        receiver.write.assert_not_called()
        receiver.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
