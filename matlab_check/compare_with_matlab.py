"""Compare the website pipeline with MATLAB's output on the same images.

usage:  python compare_with_matlab.py <matlab_reference folder> <image folder>
"""
import csv, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import pipeline as P

ref_dir, img_dir = sys.argv[1], sys.argv[2]
model = P.DRModel(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dr_model.onnx"))
rows = list(csv.DictReader(open(os.path.join(ref_dir, "matlab_reference.csv"))))

def f(x):
    try: return float(x)
    except Exception: return float("nan")

bad_mode = bad_grade = 0
dp, dc, ds, seg_agree = [], [], [], []
print("%-22s %-9s %-9s %-7s %-7s %s" % ("file", "MATLAB", "website", "dProb", "dStage1", "seg match"))
for r in rows:
    path = os.path.join(img_dir, r["file"])
    res = P.analyze(Image.open(path), model)
    m_mode, w_mode = r["mode"], res["mode"]
    line_p = line_s = float("nan")
    if m_mode != w_mode:
        bad_mode += 1
    elif w_mode in ("graded", "uncertain"):
        if int(f(r["grade"])) != res["grade"]:
            bad_grade += 1
        mp = np.array([f(r["p%d" % i]) for i in range(5)])
        line_p = float(np.abs(mp - np.array(res["probs"])).max()); dp.append(line_p)
    if res["stage1"]:
        s = res["stage1"]
        line_s = max(abs(f(r["focus"]) - s["focus"]), abs(f(r["illum"]) - s["illum"]), abs(f(r["fov"]) - s["fov"]))
        ds.append(line_s)
    seg = "-"
    segp = os.path.join(ref_dir, r["file"] + "_seg.png")
    if res["seg"] is not None and os.path.isfile(segp):
        a = np.asarray(Image.open(segp).convert("RGB").resize((512, 512), Image.NEAREST))
        agree = float((a == res["seg"]).all(axis=2).mean()); seg_agree.append(agree); seg = "%.1f%%" % (agree * 100)
    print("%-22s %-9s %-9s %-7.4f %-7.4f %s" % (r["file"][:22], m_mode, w_mode, line_p, line_s, seg))

print("\nImages compared      :", len(rows))
print("Mode mismatches      :", bad_mode, "(graded/uncertain/rejected differs)")
print("Grade mismatches     :", bad_grade)
if dp: print("Max prob difference  : %.4f" % max(dp))
if ds: print("Max Stage-1 diff     : %.4f" % max(ds))
if seg_agree: print("Segmentation pixels equal (mean): %.1f%%" % (100 * np.mean(seg_agree)))
