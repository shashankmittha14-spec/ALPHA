"""Python port of the MATLAB DR screening pipeline.

Stage 1  quality gate      (assessAndEnhanceFundus, computeFocus/Illumination/FOVScore)
Stage 2  segmentation      (segmentRetinalStructures and the detectors it calls)
Model    dr_model.onnx     (raw 0-255 pixels, channels-first, 224x224) + Grad-CAM

Where MATLAB uses toolbox functions with no exact Python twin (fibermetric,
adapthisteq 'rayleigh', imbilatfilt) the closest scikit-image equivalent is
used, so pictures can differ slightly from the MATLAB app.
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import color, exposure, filters, measure, morphology, restoration

import onnxruntime as ort

GRADES = ["No DR", "Mild", "Moderate", "Severe", "Proliferative DR"]
CONF_THRESHOLD = 0.5
CFG = dict(wFocus=0.4, wIllum=0.3, wFOV=0.3,
           focusRejectThresh=0.35, illumRejectThresh=0.35,
           fovRejectThresh=0.50, enhanceMinScore=0.30)

REASON_TEXT = {
    "blur": "the image is too blurry to assess",
    "illumination": "the image lighting is too dark/bright to assess",
    "field_of_view": "the retina is not fully/correctly framed in the image",
    "looks_like_screenshot_or_document": "this looks like a screenshot or document, not a retina photo",
    "no_retina_like_color_signature": "this image does not have the color characteristics of a retina photo",
    "not_a_color_image": "the file is not a valid color image",
}

# Segmentation colours, same as colorizeSegmentation.m (fovea is removed
# from the picture in processDRImage.m, so it is not in the legend either).
LEGEND = [("Vessel", (0, 0.4, 1)), ("Microaneurysm", (1, 1, 0)),
          ("Optic Disc", (0, 0.8, 0)), ("Hemorrhage", (0.9, 0, 0)),
          ("Exudate", (1, 0.55, 0)), ("Neovascularization", (0.9, 0, 0.9))]
CODES = dict(BG=0, VESSEL=1, OD=2, FOVEA=3, MA=4, HEM=5, EXU=6, NV=7)
SEG_SIZE = 512


def describe_reject_reason(raw):
    return "; ".join(REASON_TEXT.get(t.strip(), t.strip()) for t in raw.split("+"))


# ----------------------------------------------------------------- helpers
def rgb2gray_u8(rgb):
    g = 0.2989 * rgb[..., 0] + 0.5870 * rgb[..., 1] + 0.1140 * rgb[..., 2]
    return np.clip(np.rint(g), 0, 255).astype(np.uint8)


def normalize_score(v, lo, hi):
    return float(min(max((v - lo) / (hi - lo), 0.0), 1.0))


def mat2gray(x):
    x = x.astype(np.float64)
    lo, hi = x.min(), x.max()
    return np.zeros_like(x) if hi <= lo else (x - lo) / (hi - lo)


def imadjust(x):
    """Stretch the 1st-99th percentile of a [0,1] image to [0,1]."""
    lo, hi = np.percentile(x, [1, 99])
    if hi <= lo:
        return np.clip(x, 0, 1)
    return np.clip((x - lo) / (hi - lo), 0, 1)


def bwareaopen(bw, p):
    lab, n = ndi.label(bw, structure=np.ones((3, 3)))
    if n == 0:
        return bw.astype(bool)
    keep = np.bincount(lab.ravel()) >= p
    keep[0] = False
    return keep[lab]


def circularity(region):
    per = region.perimeter
    return 4 * np.pi * region.area / per ** 2 if per > 0 else 1.0


def dilate(mask, radius):
    if not mask.any():
        return mask.copy()
    return ndi.distance_transform_edt(~mask) <= radius


# ------------------------------------------------------- stage 1: quality
def focus_score(gray):
    a = 0.2
    k = np.array([[a, 1 - a, a], [1 - a, -4, 1 - a], [a, 1 - a, a]]) / (a + 1)
    lap = ndi.correlate(gray.astype(np.float64), k, mode="nearest")
    return normalize_score(lap.var(ddof=1), 15, 80)


def illumination_score(rgb):
    g = rgb[..., 1].astype(np.float64)
    bright = 1 - min(abs(g.mean() - 130) / 130, 1)
    contrast = normalize_score(g.std(ddof=1), 10, 40)
    return 0.5 * bright + 0.5 * contrast


def fov_score(rgb):
    gray = rgb2gray_u8(rgb)
    mask = ndi.binary_fill_holes(gray > 8)
    lab, n = ndi.label(mask, structure=np.ones((3, 3)))
    if n == 0:
        return 0.0
    largest = np.bincount(lab.ravel())[1:].max()
    rows, cols = gray.shape
    expected = np.pi * (min(rows, cols) / 2) ** 2 * 0.9
    return float(min(largest / expected, 1.0))


def enhance_image(rgb):
    lab = color.rgb2lab(rgb)
    lab[..., 0] = exposure.equalize_adapthist(lab[..., 0] / 100, clip_limit=0.01) * 100
    out = (np.clip(color.lab2rgb(lab), 0, 1) * 255).round().astype(np.uint8)
    out = restoration.denoise_bilateral(out, sigma_color=0.1, sigma_spatial=1, channel_axis=-1)
    return (np.clip(out, 0, 1) * 255).round().astype(np.uint8)


# Quality scores are measured on a copy shrunk to this long side, so big phone/web photos
# are not wrongly rejected as "blurry". Set env DR_STAGE1_LONG_SIDE=0 to measure at full
# size like the MATLAB gate (then large, smooth photos get rejected).
STD_LONG_SIDE = int(os.environ.get("DR_STAGE1_LONG_SIDE", "384"))


def standardize(rgb):
    """Shrink big photos to a standard size (never enlarge).

    The Laplacian focus score depends on image size: the same photo scores
    "blurry" at 4000 px and "sharp" at 400 px. Measuring every photo at one
    size makes the gate fair for any camera. (The MATLAB gate measured at the
    original size, so it gives different numbers for large photos.)
    """
    if STD_LONG_SIDE <= 0:
        return rgb
    h, w = rgb.shape[:2]
    s = STD_LONG_SIDE / max(h, w)
    if s >= 1:
        return rgb
    img = Image.fromarray(rgb).resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    return np.asarray(img)


def assess_and_enhance(rgb):
    c = CFG
    std = standardize(rgb)
    r = dict(focus=focus_score(rgb2gray_u8(std)), illum=illumination_score(std), fov=fov_score(std),
             was_enhanced=False)
    r["overall"] = c["wFocus"] * r["focus"] + c["wIllum"] * r["illum"] + c["wFOV"] * r["fov"]

    def failing(f, i, v):
        out = []
        if f < c["focusRejectThresh"]: out.append("blur")
        if i < c["illumRejectThresh"]: out.append("illumination")
        if v < c["fovRejectThresh"]: out.append("field_of_view")
        return out

    reasons = failing(r["focus"], r["illum"], r["fov"])
    if not reasons:
        r.update(gradable=True, reject_reason="")
        return r
    if r["overall"] < c["enhanceMinScore"]:
        r.update(gradable=False, reject_reason="+".join(reasons))
        return r

    enh = enhance_image(std)
    nf, ni = focus_score(rgb2gray_u8(enh)), illumination_score(enh)
    r["was_enhanced"] = True
    still = failing(nf, ni, r["fov"])
    if not still:
        r.update(gradable=True, reject_reason="", focus=nf, illum=ni,
                 overall=c["wFocus"] * nf + c["wIllum"] * ni + c["wFOV"] * r["fov"])
    else:
        r.update(gradable=False, reject_reason="+".join(still))
    return r


def retina_color_check(rgb):
    """Stand-in for isLikelyRetinaImage.m (that file was not provided).

    A fundus photo is red/orange in the centre and almost always has a dark
    border around a round field. Ordinary photos, screenshots and documents
    fail one of these. Images with NO dark border (tightly cropped fundus) are
    accepted only if they are strongly red-dominant.
    """
    small = np.asarray(Image.fromarray(rgb).resize((128, 128), Image.BILINEAR), dtype=np.float32)
    yy, xx = np.mgrid[0:128, 0:128]
    centre = small[np.hypot(yy - 63.5, xx - 63.5) < 38]
    cr, cg, cb = centre.mean(axis=0)
    if cr < 35 or cr < cg * 1.1 or cr < cb * 2.0:
        return False, "no_retina_like_color_signature"

    k = 16
    corners = np.concatenate([small[:k, :k].reshape(-1, 3), small[:k, -k:].reshape(-1, 3),
                              small[-k:, :k].reshape(-1, 3), small[-k:, -k:].reshape(-1, 3)])
    has_dark_border = corners.mean() < 40
    if not has_dark_border and not (cr >= cg * 1.6 and cr >= cb * 3.0):
        return False, "no_retina_like_color_signature"

    # Texture: a retina is smooth with fine vessels (moderate green-channel
    # spread). Flat colour blocks and busy everyday photos both fall outside.
    g_std = float(small[np.hypot(yy - 63.5, xx - 63.5) < 38][:, 1].std())
    if not (4.0 <= g_std <= 50.0):
        return False, "no_retina_like_color_signature"

    # Colour must be fairly uniform in hue across the field: a retina is one
    # red/orange surface, whereas photos mix many hues (blue sky, green leaves...).
    field = small[small.mean(axis=2) > 25]
    if field.size:
        redness = (field[:, 0] > field[:, 1] * 1.05) & (field[:, 0] > field[:, 2] * 1.5)
        if redness.mean() < 0.85:
            return False, "no_retina_like_color_signature"
    return True, ""


# ---------------------------------------------------- stage 2: segmentation
def locate_optic_disc(gray):
    thr = np.percentile(gray.astype(np.float64), 97, method="hazen")
    bw = bwareaopen(gray > thr, 100)
    bw = ndi.binary_fill_holes(bw)
    lab = measure.label(bw, connectivity=2)
    if lab.max() == 0:
        return np.zeros(gray.shape, bool)
    best = max(measure.regionprops(lab), key=lambda r: r.area * circularity(r))
    return lab == best.label


def locate_fovea(gray, od):
    if not od.any():
        return np.zeros(gray.shape, bool)
    r = measure.regionprops(od.astype(np.uint8))[0]
    cy, cx = r.centroid
    d = r.equivalent_diameter
    yy, xx = np.mgrid[0:gray.shape[0], 0:gray.shape[1]]
    rad = d * 1.2
    search = (np.hypot(xx - (cx + 2.5 * d), yy - cy) < rad) | (np.hypot(xx - (cx - 2.5 * d), yy - cy) < rad)
    if not search.any():
        return np.zeros(gray.shape, bool)
    g = np.where(search, gray.astype(np.float64), np.inf)
    my, mx = np.unravel_index(np.argmin(g), g.shape)
    return (xx - mx) ** 2 + (yy - my) ** 2 <= (d * 0.5) ** 2


BORDER_MARGIN = 12          # pixels (at 512x512) next to the black border of the photo
VESSEL_THRESHOLD_SCALE = 0.5   # lower = more (and fainter) vessels; 1.0 = plain Otsu
DRAW_BORDER_RING = True     # MATLAB's picture also outlines the retina edge; set False to hide it


def segment_vessels(rgb):
    adj = imadjust(rgb[..., 1].astype(np.float64) / 255)
    resp = filters.frangi(adj, sigmas=[2, 4, 6], black_ridges=True)
    # The sharp edge between the retina and the black background responds very
    # strongly. It must not set the threshold, so the threshold is worked out
    # from the inside of the retina only.
    fov = ndi.binary_fill_holes(rgb2gray_u8(rgb) > 8)
    inner = ndi.distance_transform_edt(fov) > BORDER_MARGIN
    if inner.sum() < 100 or (resp * inner).max() <= 0:
        return np.zeros(adj.shape, bool)
    r = resp / (resp * inner).max()
    level = filters.threshold_otsu(np.clip(r[inner], 0, 1)) * VESSEL_THRESHOLD_SCALE
    mask = r > level
    if not DRAW_BORDER_RING:
        mask &= inner
    return bwareaopen(mask, 30)


def detect_microaneurysms(rgb, vessel):
    inv = 1 - mat2gray(rgb[..., 1])
    th = imadjust(morphology.white_tophat(inv, morphology.disk(5)))
    if th.max() <= th.min():
        return np.zeros(th.shape, bool)
    bw = (th > filters.threshold_otsu(th)) & ~dilate(vessel, 2)
    bw = bwareaopen(bw, 2)
    out = np.zeros(bw.shape, bool)
    for r in measure.regionprops(measure.label(bw, connectivity=2)):
        if r.area <= 40 and circularity(r) > 0.6:
            out[tuple(r.coords.T)] = True
    return out


def detect_hem_exu(rgb, vessel, od):
    g, rd = mat2gray(rgb[..., 1]), mat2gray(rgb[..., 0])
    dark = (g < filters.threshold_otsu(g) * 0.7) & ~dilate(vessel, 2) & ~od
    dark = bwareaopen(dark, 15)
    hem = np.zeros(dark.shape, bool)
    for r in measure.regionprops(measure.label(dark, connectivity=2)):
        if 15 < r.area < 3000:
            hem[tuple(r.coords.T)] = True
    exu = bwareaopen(((g > 0.85) & (rd > 0.85)) & ~od, 15)
    return hem, exu


def detect_neovascularization(vessel, od):
    if not od.any():
        return np.zeros(vessel.shape, bool)
    od_d = dilate(od, 40)
    skel = morphology.skeletonize(vessel)
    nb = ndi.convolve(skel.astype(int), np.ones((3, 3), int), mode="constant") - skel
    near = skel & (nb >= 3) & od_d
    dens = ndi.gaussian_filter(near.astype(np.float64), 5)
    ref = dens[od_d].mean() + np.finfo(float).eps
    return (dens > 2 * ref) & od_d


def segment_retinal_structures(rgb):
    """rgb: uint8 SEG_SIZE x SEG_SIZE x 3 -> (label mask, coloured picture)."""
    gray = rgb2gray_u8(rgb)
    od = locate_optic_disc(gray)
    vessel = segment_vessels(rgb)
    ma = detect_microaneurysms(rgb, vessel)
    hem, exu = detect_hem_exu(rgb, vessel, od)
    nv = detect_neovascularization(vessel, od)
    lab = np.zeros(gray.shape, np.uint8)
    lab[vessel] = CODES["VESSEL"]; lab[ma] = CODES["MA"]; lab[hem] = CODES["HEM"]
    lab[exu] = CODES["EXU"]; lab[nv] = CODES["NV"]; lab[od] = CODES["OD"]
    palette = {CODES["VESSEL"]: LEGEND[0][1], CODES["MA"]: LEGEND[1][1], CODES["OD"]: LEGEND[2][1],
               CODES["HEM"]: LEGEND[3][1], CODES["EXU"]: LEGEND[4][1], CODES["NV"]: LEGEND[5][1]}
    rgb_out = np.zeros(gray.shape + (3,), np.uint8)
    for code, c in palette.items():
        rgb_out[lab == code] = [int(round(v * 255)) for v in c]
    return lab, rgb_out


# ------------------------------------------------------- model + Grad-CAM
_PASS = {"Flatten", "Reshape", "Squeeze", "Unsqueeze", "Identity", "Transpose", "Cast"}


def _find_cam_layout(model):
    """Find (feature tensor feeding global-average-pool, FC weights [K, C])."""
    from onnx import numpy_helper
    g = model.graph
    prod = {o: n for n in g.node for o in n.output}
    inits = {i.name: numpy_helper.to_array(i) for i in g.initializer}

    n = prod.get(g.output[0].name)
    for _ in range(10):
        if n is None or n.op_type == "Softmax":
            break
        n = prod.get(n.input[0])
    if n is None or n.op_type != "Softmax":
        return None
    t, W, x = n.input[0], None, None
    for _ in range(12):
        n = prod.get(t)
        if n is None:
            return None
        op = n.op_type
        if op == "Gemm":
            B = inits.get(n.input[1])
            if B is None: return None
            a = next((at.f for at in n.attribute if at.name == "alpha"), 1.0)
            tb = next((at.i for at in n.attribute if at.name == "transB"), 0)
            W, x = (B if tb else B.T) * a, n.input[0]
            break
        if op == "MatMul":
            if n.input[1] in inits: W, x = inits[n.input[1]].T, n.input[0]
            elif n.input[0] in inits: W, x = inits[n.input[0]], n.input[1]
            else: return None
            break
        if op == "Conv":
            B = inits.get(n.input[1])
            if B is None or B.shape[2:] != (1, 1): return None
            W, x = B.reshape(B.shape[0], B.shape[1]), n.input[0]
            break
        if op == "Add":
            non = [i for i in n.input if i not in inits]
            if len(non) != 1: return None
            t = non[0]
        elif op in _PASS:
            t = n.input[0]
        else:
            return None
    if W is None:
        return None
    t = x
    for _ in range(12):
        n = prod.get(t)
        if n is None:
            return None
        if n.op_type in ("GlobalAveragePool", "ReduceMean"):
            return n.input[0], np.asarray(W, np.float64)
        if n.op_type in _PASS:
            t = n.input[0]
        else:
            return None
    return None


def _jet(x):
    r = np.clip(1.5 - np.abs(4 * x - 3), 0, 1)
    g = np.clip(1.5 - np.abs(4 * x - 2), 0, 1)
    b = np.clip(1.5 - np.abs(4 * x - 1), 0, 1)
    return np.stack([r, g, b], -1)


class DRModel:
    def __init__(self, path):
        self.feature_name, self.W = None, None
        data = path
        try:
            import onnx
            from onnx import TensorProto, helper
            model = onnx.load(path)
            layout = _find_cam_layout(model)
            if layout:
                self.feature_name, self.W = layout
                model.graph.output.append(
                    helper.make_tensor_value_info(self.feature_name, TensorProto.FLOAT, None))
                data = model.SerializeToString()
        except Exception as e:  # heat-map is optional; scores must still work
            print("Grad-CAM disabled:", e)
            self.feature_name, self.W, data = None, None, path
        self.sess = ort.InferenceSession(data, providers=["CPUExecutionProvider"])
        self.input_name = self.sess.get_inputs()[0].name
        self.has_cam = self.feature_name is not None
        if self.has_cam and self.sess.get_outputs()[0].name == self.feature_name:
            self.has_cam = False

    def predict(self, img224):
        x = np.transpose(img224.astype(np.float32), (2, 0, 1))[None]
        outs = self.sess.run(None, {self.input_name: x})
        probs = outs[0].flatten()
        feats = outs[1][0] if self.has_cam and len(outs) > 1 else None
        return probs, feats

    def grad_cam(self, probs, feats, cls, size=224):
        """Grad-CAM of the softmax score of class `cls` (same target as the MATLAB app)."""
        if feats is None or self.W is None:
            return None
        W = self.W if self.W.shape[0] == len(probs) else self.W.T
        p = probs.astype(np.float64)
        dS = p[cls] * ((np.arange(len(p)) == cls).astype(np.float64) - p)
        c, h, w = feats.shape
        alpha = (dS @ W) / (h * w)
        cam = np.maximum(np.tensordot(alpha, feats.astype(np.float64), axes=(0, 0)), 0)
        if cam.max() <= 0:
            # Softmax saturated (score ~1.0), so its gradient vanishes. Fall back to the
            # class-logit weights, which gives the same map up to scale.
            cam = np.maximum(np.tensordot(W[cls] / (h * w), feats.astype(np.float64), axes=(0, 0)), 0)
        cam = np.asarray(Image.fromarray(cam.astype(np.float32), mode="F").resize((size, size), Image.BICUBIC))
        cam = np.clip(cam, 0, None)
        return mat2gray(cam) if cam.max() > 0 else np.zeros_like(cam)


def heat_overlay(rgb512, cam):
    cam512 = np.asarray(Image.fromarray(cam.astype(np.float32), mode="F").resize((SEG_SIZE, SEG_SIZE), Image.BICUBIC))
    cam512 = np.clip(cam512, 0, 1)
    out = 0.5 * rgb512.astype(np.float64) + 0.5 * _jet(cam512) * 255
    return np.clip(out, 0, 255).astype(np.uint8)


# ------------------------------------------------------------- full pipeline
def urgency_for(grade):
    if grade in (0, 1):
        return "Routine follow-up (annual screening)", "routine"
    if grade == 2:
        return "Refer to ophthalmologist within a few weeks", "soon"
    return "URGENT referral to ophthalmologist required", "urgent"


def analyze(pil_img, model, conf_threshold=CONF_THRESHOLD):
    res = dict(mode="", message="", stage1=None, grade=None, grade_name="", confidence=None,
               probs=None, urgency=None, urgency_level=None, orig=None, heat=None, seg=None,
               heat_available=model.has_cam)
    if pil_img.mode in ("L", "1", "LA", "I", "I;16", "F"):
        res.update(mode="rejected", reject_reason="not_a_color_image",
                   message="Rejected: " + describe_reject_reason("not_a_color_image"))
        res["orig"] = np.asarray(pil_img.convert("RGB").resize((SEG_SIZE, SEG_SIZE), Image.BICUBIC))
        return res

    rgb = np.asarray(pil_img.convert("RGB"))
    res["orig"] = np.asarray(Image.fromarray(rgb).resize((SEG_SIZE, SEG_SIZE), Image.BICUBIC))

    ok, why = retina_color_check(rgb)
    if not ok:
        res.update(mode="rejected", reject_reason=why,
                   message="Rejected: " + describe_reject_reason(why))
        return res

    s1 = assess_and_enhance(rgb)
    res["stage1"] = s1
    if not s1["gradable"]:
        res.update(mode="rejected", reject_reason=s1["reject_reason"],
                   message="Rejected: " + describe_reject_reason(s1["reject_reason"]))
        return res

    img224 = np.asarray(Image.fromarray(rgb).resize((224, 224), Image.BICUBIC))
    probs, feats = model.predict(img224)
    idx = int(np.argmax(probs))
    conf = float(probs[idx])
    res.update(probs=[float(p) for p in probs], grade=idx, grade_name=GRADES[idx], confidence=conf)

    if conf < conf_threshold:
        res.update(mode="uncertain",
                   message="Prediction uncertain (top confidence %.0f%%) -- manual review recommended" % (conf * 100))
        return res

    cam = model.grad_cam(probs, feats, idx)
    if cam is not None:
        res["heat"] = heat_overlay(res["orig"], cam)
    try:
        _, res["seg"] = segment_retinal_structures(res["orig"])
    except Exception as e:
        print("Segmentation failed:", e)
    text, level = urgency_for(idx)
    res.update(mode="graded", urgency=text, urgency_level=level,
               message="Prediction: Grade %d (%s) -- confidence %.0f%%" % (idx, GRADES[idx], conf * 100))
    return res
