"""Kokoro TTS — minimal kokoro-onnx server."""
import os
import io
import hashlib
import subprocess
import numpy as np
import soundfile as sf
from flask import Flask, request, jsonify
from google.cloud import storage

app = Flask(__name__)

_kokoro = None
_bucket = None
BUCKET = os.environ.get("AUDIO_CACHE_BUCKET", "driveguide-audio-cache")
DEFAULT_VOICE = "af_heart"


def get_kokoro():
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro("/app/kokoro-v1.0.onnx", "/app/voices-v1.0.bin")
        app.logger.info("Kokoro loaded")
    return _kokoro


def get_bucket():
    global _bucket
    if _bucket is None:
        _bucket = storage.Client().bucket(BUCKET)
    return _bucket


def sanitize_for_speech(text):
    """Strip markdown/symbols that TTS would annunciate literally."""
    import re
    text = re.sub(r'\*{1,3}([^*]+)\*{1,3}', r'\1', text)
    text = re.sub(r'^#{1,6}\s*', '', text, flags=re.MULTILINE)
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = re.sub(r'`([^`]+)`', r'\1', text)
    text = re.sub(r'_([^_]+)_', r'\1', text)
    text = re.sub(r'#(\w)', r'\1', text)
    text = re.sub(r'[~^{}|\\]', '', text)
    # Expand abbreviations
    for abbr, full in {"St. ": "Street ", "Ave. ": "Avenue ", "Blvd. ": "Boulevard ",
                        "Dr. ": "Drive ", "Rd. ": "Road ", "Mt. ": "Mount "}.items():
        text = text.replace(abbr, full)
    return text.strip()


def to_mp3(samples, sr):
    buf = io.BytesIO()
    sf.write(buf, samples, sr, format="WAV")
    wav = buf.getvalue()
    try:
        r = subprocess.run(
            ["ffmpeg", "-i", "pipe:0", "-f", "mp3", "-ab", "128k", "-ac", "1", "-ar", "24000", "-y", "pipe:1"],
            input=wav, capture_output=True, timeout=10)
        if r.returncode == 0 and len(r.stdout) > 100:
            return r.stdout, "audio/mpeg"
    except Exception:
        pass
    return wav, "audio/wav"


@app.route("/health")
def health():
    return jsonify({"status": "ok", "engine": "kokoro-onnx"})


@app.route("/synthesize", methods=["POST"])
def synthesize():
    data = request.get_json()
    text = sanitize_for_speech(data.get("text", ""))
    voice = data.get("voice", DEFAULT_VOICE)
    speed = float(data.get("speed", 0.95))
    content_hash = data.get("content_hash") or hashlib.sha256(text.encode()).hexdigest()[:16]

    gcs_path = f"audio/kokoro-{content_hash}.mp3"
    bucket = get_bucket()
    blob = bucket.blob(gcs_path)
    if blob.exists():
        return jsonify({"audio_url": f"https://storage.googleapis.com/{BUCKET}/{gcs_path}", "content_hash": content_hash, "cached": True})

    kokoro = get_kokoro()
    samples, sr = kokoro.create(text, voice=voice, speed=speed)
    dur = len(samples) / sr
    mp3, ct = to_mp3(samples, sr)

    blob.upload_from_string(mp3, content_type=ct)
    blob.cache_control = "public, max-age=31536000"
    blob.patch()

    return jsonify({"audio_url": f"https://storage.googleapis.com/{BUCKET}/{gcs_path}",
                     "duration_seconds": round(dur, 1), "file_size_bytes": len(mp3),
                     "content_hash": content_hash, "cached": False})


@app.route("/batch", methods=["POST"])
def batch():
    data = request.get_json()
    segs = data.get("segments", [])
    voice = data.get("voice", DEFAULT_VOICE)
    speed = float(data.get("speed", 0.95))
    bucket = get_bucket()
    kokoro = get_kokoro()

    results, td, ts = [], 0, 0
    for s in segs:
        text = sanitize_for_speech(s.get("narration_text", ""))
        ch = s.get("content_hash", "")
        sid = s.get("id", "")
        if not text:
            continue

        gcs_path = f"audio/kokoro-{ch}.mp3"
        blob = bucket.blob(gcs_path)
        if blob.exists():
            results.append({"segment_id": sid, "audio_url": f"https://storage.googleapis.com/{BUCKET}/{gcs_path}",
                            "duration_seconds": 0, "file_size_bytes": 0, "content_hash": ch})
            continue

        samples, sr = kokoro.create(text, voice=voice, speed=speed)
        dur = len(samples) / sr
        mp3, ct = to_mp3(samples, sr)
        blob.upload_from_string(mp3, content_type=ct)
        blob.cache_control = "public, max-age=31536000"
        blob.patch()

        results.append({"segment_id": sid, "audio_url": f"https://storage.googleapis.com/{BUCKET}/{gcs_path}",
                         "duration_seconds": round(dur, 1), "file_size_bytes": len(mp3), "content_hash": ch})
        td += dur
        ts += len(mp3)

    return jsonify({"segments": results, "total_duration_seconds": round(td), "total_size_bytes": ts})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
