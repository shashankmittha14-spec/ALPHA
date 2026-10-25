"""DR screening website - pure Python (ONNX model), no MATLAB needed.

Runs anywhere: your PC, Hugging Face Spaces, Render, etc.
Uploaded images are processed in memory and never saved to disk.
"""
import base64
import io
import os
from pathlib import Path

import numpy as np
from flask import Flask, Response, jsonify, request, send_from_directory
from PIL import Image

import pipeline as P
import report as R

BASE = Path(__file__).resolve().parent
MODEL_PATH = os.environ.get("DR_MODEL", str(BASE / "dr_model.onnx"))

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 15 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 60_000_000  # guard against decompression bombs

MODEL = P.DRModel(MODEL_PATH)
print("Model loaded. Grad-CAM available:", MODEL.has_cam)


def _png_url(arr):
    if arr is None:
        return None
    buf = io.BytesIO()
    Image.fromarray(np.asarray(arr, dtype=np.uint8)).save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


MAX_SIDE = int(os.environ.get("DR_MAX_SIDE", "1600"))  # keeps memory low on small free servers


def _open(raw):
    img = Image.open(io.BytesIO(raw))
    if img.format == "JPEG":
        img.draft("RGB", (MAX_SIDE, MAX_SIDE))  # decode big JPEGs at reduced size (saves RAM)
    img.load()
    if max(img.size) > MAX_SIDE:
        img.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    return img


def _to_json(res):
    s1 = res.get("stage1")
    stage1 = None
    if s1:
        stage1 = {k: (round(float(s1[k]), 3)) for k in ("focus", "illum", "fov", "overall")}
        stage1["gradable"] = bool(s1.get("gradable"))
        stage1["was_enhanced"] = bool(s1.get("was_enhanced"))
    status = {"graded": "ok", "uncertain": "uncertain", "rejected": "rejected"}.get(res["mode"], "error")
    return {
        "status": status,
        "message": res["message"],
        "stage1": stage1,
        "grade": res["grade"],
        "grade_name": res["grade_name"],
        "confidence": res["confidence"],
        "dr_detected": None if res["grade"] is None else res["grade"] > 0,
        "probs": res["probs"],
        "grades": P.GRADES,
        "urgency": res["urgency"],
        "urgency_level": res["urgency_level"],
        "images": {"original": _png_url(res["orig"]),
                   "heatmap": _png_url(res["heat"]),
                   "segmentation": _png_url(res["seg"])},
        "heatmap_available": res["heat"] is not None,
        "legend": [{"name": n, "color": "rgb(%d,%d,%d)" % tuple(int(v * 255) for v in c)}
                   for n, c in P.LEGEND],
    }


@app.get("/")
def index():
    return send_from_directory(str(BASE), "index.html")


@app.get("/health")
def health():
    return jsonify(ok=True, gradcam=MODEL.has_cam)


@app.errorhandler(413)
def too_large(_e):
    return jsonify(status="error", message="File too large (15 MB max)."), 413


@app.post("/predict")
def predict():
    f = request.files.get("image")
    if f is None:
        return jsonify(status="error", message="No image received."), 400
    try:
        img = _open(f.read())
    except Exception:
        return jsonify(status="error", message="Could not read this file as an image."), 400
    try:
        return jsonify(_to_json(P.analyze(img, MODEL)))
    except Exception as e:
        print("predict error:", repr(e))
        return jsonify(status="error", message="Processing failed. Please try another image."), 500


@app.post("/report")
def report():
    f = request.files.get("image")
    if f is None:
        return jsonify(status="error", message="No image received."), 400
    try:
        img = _open(f.read())
        res = P.analyze(img, MODEL)
        pdf = R.build_pdf(res, f.filename or "image.jpg",
                          captured_by=request.form.get("captured_by", ""),
                          device_used=request.form.get("device_used", ""))
        return Response(pdf, mimetype="application/pdf",
                        headers={"Content-Disposition": "attachment; filename=DR_Report.pdf"})
    except Exception as e:
        print("report error:", repr(e))
        return jsonify(status="error", message="Report failed."), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)))
