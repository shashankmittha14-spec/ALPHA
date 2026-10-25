"""PDF report in the style of the MATLAB generateReportPDF.m (reportlab)."""
import io
import os
import zlib
from datetime import datetime

import numpy as np
from PIL import Image
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (Image as RLImage, KeepTogether, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

from pipeline import GRADES, LEGEND, describe_reject_reason

NAVY = colors.Color(0.10, 0.28, 0.45)
GRID = colors.Color(0.75, 0.75, 0.75)
HEAD_BG = colors.Color(0.90, 0.92, 0.96)

S_BODY = ParagraphStyle("body", fontName="Helvetica", fontSize=9.5, leading=12, alignment=1)
S_SMALL = ParagraphStyle("small", fontName="Helvetica", fontSize=7.5, leading=9.5)
S_SECT = ParagraphStyle("sect", fontName="Helvetica-Bold", fontSize=11, leading=14, spaceBefore=6, spaceAfter=3)
S_SUB = ParagraphStyle("sub", fontName="Helvetica-Bold", fontSize=9.5, leading=12, spaceBefore=6, spaceAfter=2)
S_MONO = ParagraphStyle("mono", fontName="Courier", fontSize=8.5, leading=11)
S_CELL = ParagraphStyle("cell", fontName="Helvetica", fontSize=8.5, leading=10.5)
S_CELLB = ParagraphStyle("cellb", fontName="Helvetica-Bold", fontSize=8.5, leading=10.5)
S_CAP = ParagraphStyle("cap", fontName="Helvetica", fontSize=8.5, leading=10, alignment=1)


def _png(arr, size):
    b = io.BytesIO()
    Image.fromarray(arr).save(b, "PNG")
    b.seek(0)
    return RLImage(b, width=size, height=size)


def _table(headers, rows, widths):
    data = [[Paragraph(h, S_CELLB) for h in headers]] + \
           [[Paragraph(str(c), S_CELL) for c in r] for r in rows]
    t = Table(data, colWidths=widths)
    t.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.5, GRID),
        ("BACKGROUND", (0, 0), (-1, 0), HEAD_BG),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2)]))
    return t


def _banner(text, fg, bg):
    p = Paragraph('<font color="#%02x%02x%02x"><b>%s</b></font>' % (
        int(fg[0] * 255), int(fg[1] * 255), int(fg[2] * 255), text),
        ParagraphStyle("b", fontName="Helvetica-Bold", fontSize=13, leading=16, alignment=1))
    t = Table([[p]], colWidths=[174 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.Color(*bg)),
                           ("BOX", (0, 0), (-1, -1), 0.5, GRID),
                           ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    return t


def _body(text, rgb=(0, 0, 0)):
    return Paragraph('<font color="#%02x%02x%02x">%s</font>' % (
        int(rgb[0] * 255), int(rgb[1] * 255), int(rgb[2] * 255), text), S_BODY)


def _esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _stage1_rows(s):
    return [("Focus Score", "%.3f" % s["focus"], ">= 0.35"),
            ("Illumination Score", "%.3f" % s["illum"], ">= 0.35"),
            ("Field-of-View Score", "%.3f" % s["fov"], ">= 0.50")]


def _explain(story):
    story.append(Paragraph("What These Scores Mean", S_SUB))
    for line in (
        "Focus Score (0-1): sharpness of the image. Low scores indicate blur that can hide fine lesions.",
        "Illumination Score (0-1): exposure/contrast quality. Low scores indicate under/over-exposed capture.",
        "Field-of-View Score (0-1): how much of the expected retinal field is captured. Low scores indicate cropping or obstruction.",
        "An image must clear all three minimum thresholds to be marked Gradable and proceed to DR classification."):
        story.append(Paragraph(line, S_SMALL))


def _causes(story):
    story.append(Paragraph("How Diabetic Retinopathy Develops", S_SUB))
    story.append(Paragraph(
        "Chronic high blood sugar progressively damages small retinal blood vessels. This begins with "
        "microaneurysms (early vessel bulges), which can progress to hemorrhages and fluid/lipid leakage "
        "(exudates), and in advanced stages triggers abnormal new vessel growth (neovascularization), "
        "which can bleed and cause vision loss if untreated.", S_SMALL))


def _icdr(story):
    story.append(KeepTogether([Paragraph("ICDR Severity Scale (Reference)", S_SECT), _table(["Grade", "Category", "Defining Feature"], [
        ("0", "No DR", "No visible abnormalities"),
        ("1", "Mild NPDR", "Microaneurysms only"),
        ("2", "Moderate NPDR", "More than microaneurysms, less than severe"),
        ("3", "Severe NPDR", "Extensive hemorrhages/microaneurysms, venous beading, or IRMA"),
        ("4", "Proliferative DR", "Neovascularization or vitreous/preretinal hemorrhage")],
        [18 * mm, 42 * mm, 114 * mm])]))


def _validation(story):
    story.append(Paragraph("System Validation Summary", S_SECT))
    t = Table([[Paragraph(
        "Prototype check on 100 validation images: DR found in about 81% of images with DR, healthy images "
        "cleared in about 79%, exact grade correct in about 60% of confident results. Small test, not a "
        "clinical study.", ParagraphStyle("v", fontName="Helvetica", fontSize=7.5, leading=9.5, alignment=1))]],
        colWidths=[174 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.Color(0.93, 0.96, 0.93)),
                           ("BOX", (0, 0), (-1, -1), 0.5, GRID)]))
    story.append(t)


def _footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(colors.Color(0.8, 0.8, 0.8))
    canvas.line(18 * mm, 18 * mm, 192 * mm, 18 * mm)
    canvas.setFont("Helvetica", 7)
    canvas.setFillColor(colors.Color(0.45, 0.45, 0.45))
    canvas.drawCentredString(105 * mm, 13.5 * mm,
        "This report is generated by an AI-assisted screening tool and is intended to support, not replace, clinical judgement.")
    canvas.drawCentredString(105 * mm, 10 * mm,
        "All flagged cases should be reviewed by a qualified professional.")
    canvas.setFont("Helvetica", 6.5)
    canvas.setFillColor(colors.Color(0.6, 0.6, 0.6))
    canvas.drawCentredString(105 * mm, 6 * mm,
        "Model: DR-CNN v1 (ONNX)  |  Pipeline: Python port of the MATLAB pipeline  |  Report Engine: web report v1")
    canvas.restoreState()


def build_pdf(res, source_name, captured_by="", device_used=""):
    """res: result dict from pipeline.analyze. Returns PDF bytes."""
    base = os.path.splitext(os.path.basename(source_name or "image"))[0]
    now = datetime.now()
    rid = "AALPHA-%s-%04X" % (now.strftime("%Y%m%d%H%M%S"), zlib.crc32(base.encode()) & 0xFFFF)
    mode = res["mode"]
    stage = {"rejected": "Stage 1 - Quality Gate",
             "uncertain": "Stage 2 - Classification (low confidence)",
             "graded": "Stage 2 - Classification"}[mode]

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm,
                            topMargin=12 * mm, bottomMargin=22 * mm,
                            title="DR Screening Report " + rid)
    story = []

    head = Table([[Paragraph('<font color="white"><b>AI-Based Diabetic Retinopathy Screening</b></font>',
                             ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=14, leading=17)),
                   Paragraph('<font color="#d9e6ff">Team AALPHA</font>',
                             ParagraphStyle("h2", fontName="Helvetica", fontSize=9, leading=11, alignment=2))]],
                 colWidths=[110 * mm, 64 * mm])
    head.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), NAVY), ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                              ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
    story += [head, Spacer(1, 4 * mm)]

    blank = "______________________"
    left = "Report ID      : %s<br/>Image ID       : %s<br/>Source File    : %s<br/>Screening Date : %s" % (
        rid, _esc(base), _esc(os.path.basename(source_name or "")), now.strftime("%d/%m/%Y"))
    right = "Time           : %s<br/>Pipeline Stage : %s<br/>Captured By    : %s<br/>Device Used    : %s" % (
        now.strftime("%I:%M:%S %p"), stage, _esc(captured_by) or blank, _esc(device_used) or blank)
    info = Table([[Paragraph(left, S_MONO), Paragraph(right, S_MONO)]], colWidths=[80 * mm, 94 * mm])
    info.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, 0), 0.5, GRID),
                              ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story += [info, Spacer(1, 3 * mm)]

    s1 = res.get("stage1")
    if mode == "rejected":
        story.append(_banner("IMAGE REJECTED -- NOT PROCESSED", (0.7, 0, 0), (1, 0.9, 0.9)))
        story.append(Spacer(1, 2 * mm))
        story.append(_body("Reason: " + _esc(describe_reject_reason(res.get("reject_reason", "")))))
        story.append(Spacer(1, 2 * mm))
        story.append(_png(res["orig"], 60 * mm))
        story.append(Paragraph("Uploaded Image", S_CAP))
        story.append(Paragraph("Test Report", S_SECT))
        if s1:
            rows = _stage1_rows(s1) + [("Overall Score", "%.3f" % s1["overall"], "--"),
                                       ("Gradable", "False", "--")]
        else:
            rows = [("Retina colour check", "not passed", "red-dominant retina colours")]
        story.append(_table(["Metric", "Result", "Reference"], rows, [73 * mm, 38 * mm, 63 * mm]))
        _explain(story)
        _validation(story)

    elif mode == "uncertain":
        story.append(_banner("PREDICTION UNCERTAIN (confidence %.0f%%)" % (res["confidence"] * 100),
                             (0.7, 0.5, 0), (1, 0.95, 0.8)))
        story.append(Spacer(1, 2 * mm))
        story.append(_body("Recommendation: manual review by a qualified professional required."))
        story.append(Spacer(1, 2 * mm))
        story.append(_png(res["orig"], 60 * mm))
        story.append(Paragraph("Uploaded Image", S_CAP))
        story.append(Paragraph("Test Report", S_SECT))
        rows = _stage1_rows(s1) + [("Overall Score", "%.3f" % s1["overall"], "--"),
                                   ("Model Confidence", "%.0f%%" % (res["confidence"] * 100), ">= 50%")]
        story.append(_table(["Metric", "Result", "Reference"], rows, [73 * mm, 38 * mm, 63 * mm]))
        _explain(story)
        _validation(story)

    else:  # graded
        colour = {"routine": (0, 0.5, 0), "soon": (0.85, 0.55, 0), "urgent": (0.8, 0, 0)}[res["urgency_level"]]
        story.append(_banner("Grade %d (%s)  |  Confidence %.0f%%" % (
            res["grade"], res["grade_name"], res["confidence"] * 100), (0.15, 0.15, 0.15), (0.94, 0.94, 0.94)))
        story.append(Spacer(1, 2 * mm))
        story.append(_body("<b>Referral Urgency: %s</b>" % _esc(res["urgency"]), colour))
        story.append(Spacer(1, 3 * mm))

        size = 54 * mm
        def cell(arr, cap):
            if arr is None:
                return [Paragraph("Unavailable", S_CAP), Paragraph(cap, S_CAP)]
            return [_png(arr, size), Paragraph(cap, S_CAP)]
        trio = Table([[cell(res["orig"], "Original"), cell(res["heat"], "Grad-CAM (Explainable AI)"),
                       cell(res["seg"], "Segmentation")]], colWidths=[58 * mm] * 3)
        trio.setStyle(TableStyle([("ALIGN", (0, 0), (-1, -1), "CENTER"), ("VALIGN", (0, 0), (-1, -1), "TOP")]))
        story += [trio, Spacer(1, 2 * mm)]

        story.append(Paragraph("Segmentation Legend:", S_SUB))
        items = []
        for name, c in LEGEND:
            sw = Table([[""]], colWidths=[4 * mm], rowHeights=[4 * mm])
            sw.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.Color(*c))]))
            items.append([sw, Paragraph(name, S_SMALL)])
        half = (len(items) + 1) // 2
        rows = []
        for i in range(half):
            row = items[i] + (items[i + half] if i + half < len(items) else ["", ""])
            rows.append(row)
        leg = Table(rows, colWidths=[6 * mm, 40 * mm, 6 * mm, 40 * mm])
        leg.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                                 ("TOPPADDING", (0, 0), (-1, -1), 1), ("BOTTOMPADDING", (0, 0), (-1, -1), 1)]))
        leg.hAlign = "LEFT"
        story.append(leg)

        story.append(Paragraph("Test Report", S_SECT))
        rows = _stage1_rows(s1) + [("Overall Quality", "%.3f" % s1["overall"], "--"),
                                   ("Predicted DR Grade", "%d (%s)" % (res["grade"], res["grade_name"]), "0-4"),
                                   ("Model Confidence", "%.0f%%" % (res["confidence"] * 100), ">= 50%")]
        story.append(_table(["Metric", "Result", "Reference"], rows, [73 * mm, 38 * mm, 63 * mm]))
        story.append(Spacer(1, 2 * mm))
        story.append(Paragraph(
            "Note: the segmentation is a rule-based estimate. Microaneurysm and neovascularization marks are "
            "the least reliable and should not be used on their own.", S_SMALL))
        _explain(story)
        _causes(story)
        _icdr(story)
        _validation(story)

    doc.build(story, onFirstPage=_footer, onLaterPages=_footer)
    return buf.getvalue()
