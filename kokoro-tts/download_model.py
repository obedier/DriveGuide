"""Download Kokoro ONNX model files."""
import urllib.request
import os

BASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
FILES = ["kokoro-v1.0.onnx", "voices-v1.0.bin"]

for f in FILES:
    path = f"/app/{f}"
    if not os.path.exists(path):
        print(f"Downloading {f}...")
        urllib.request.urlretrieve(f"{BASE}/{f}", path)
        size_mb = os.path.getsize(path) / 1024 / 1024
        print(f"Downloaded {f}: {size_mb:.1f} MB")
    else:
        print(f"{f} already exists")

print("All model files ready")
