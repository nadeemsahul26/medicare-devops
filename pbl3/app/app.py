"""MediCare Patient Portal - a small healthcare web app used for the DevOps PBL-III demos.

Dynamic features:
  * Vitals checker (BMI, blood pressure, blood sugar -> risk flags), computed per request
  * Patient directory with PII masking (synthetic data only)
  * /health and /api/info endpoints used by Jenkins smoke tests

The banner shows the version, deployment colour and pod name, so you can SEE
rolling updates (PBL 7) and blue-green switches (PBL 8) happen live.
"""
import logging
import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template, request

app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("APP_SECRET_KEY", "dev-only-not-secret")

APP_VERSION = os.environ.get("APP_VERSION", "v1")
APP_COLOR = os.environ.get("APP_COLOR", "blue")          # blue | green
PBL_MODE = os.environ.get("PBL_MODE", "local")            # pbl7 | pbl8 | pbl9 | local
HOSTNAME = socket.gethostname()
_RELEASE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "release.txt")
try:
    with open(_RELEASE_FILE, encoding="utf-8") as fh:
        RELEASE_NOTE = fh.read().strip()
except OSError:
    RELEASE_NOTE = ""

logging.basicConfig(level=logging.INFO, format="%(asctime)s AUDIT %(message)s")
audit = logging.getLogger("audit")

# Synthetic demo data - no real patients.
PATIENTS = [
    {"id": "PT-1001", "name": "Arun Kumar", "phone": "9876543210", "ward": "Cardiology"},
    {"id": "PT-1002", "name": "Meena Ravi", "phone": "9123456780", "ward": "Endocrinology"},
    {"id": "PT-1003", "name": "Joseph Daniel", "phone": "9988776655", "ward": "General Medicine"},
    {"id": "PT-1004", "name": "Fathima Begum", "phone": "9001122334", "ward": "Orthopaedics"},
]


def mask_phone(phone: str) -> str:
    """Show only the last 4 digits (data minimisation for patient privacy)."""
    return "X" * (len(phone) - 4) + phone[-4:]


def mask_name(name: str) -> str:
    return " ".join(part[0] + "*" * (len(part) - 1) for part in name.split())


def assess_vitals(weight_kg: float, height_cm: float, systolic: int, sugar: int) -> dict:
    """Simple rule-based screening. Educational only - not medical advice."""
    if weight_kg <= 0 or height_cm <= 0:
        raise ValueError("weight and height must be positive")
    bmi = round(weight_kg / ((height_cm / 100) ** 2), 1)
    if bmi < 18.5:
        bmi_cat = "Underweight"
    elif bmi < 25:
        bmi_cat = "Normal"
    elif bmi < 30:
        bmi_cat = "Overweight"
    else:
        bmi_cat = "Obese"

    flags = []
    if systolic >= 140:
        flags.append("High blood pressure (stage 2 range)")
    elif systolic >= 130:
        flags.append("Elevated blood pressure (stage 1 range)")
    if sugar >= 126:
        flags.append("Fasting sugar in diabetic range")
    elif sugar >= 100:
        flags.append("Fasting sugar in pre-diabetic range")
    if bmi >= 30:
        flags.append("BMI in obese range")

    risk = "Low" if not flags else ("Moderate" if len(flags) == 1 else "High")
    return {"bmi": bmi, "bmi_category": bmi_cat, "flags": flags, "risk": risk}


@app.after_request
def security_headers(resp):
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; style-src 'self' 'unsafe-inline'; "
        "form-action 'self'; frame-ancestors 'none'"
    )
    resp.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
    resp.headers["Cache-Control"] = "no-store"
    return resp


def banner():
    return {"version": APP_VERSION, "color": APP_COLOR, "pod": HOSTNAME, "mode": PBL_MODE, "note": RELEASE_NOTE}


@app.route("/", methods=["GET", "POST"])
def index():
    result, error = None, None
    if request.method == "POST":
        try:
            result = assess_vitals(
                float(request.form["weight"]),
                float(request.form["height"]),
                int(request.form["systolic"]),
                int(request.form["sugar"]),
            )
            audit.info("vitals_check pod=%s risk=%s", HOSTNAME, result["risk"])
        except (KeyError, ValueError):
            error = "Please enter valid positive numbers in every field."
    return render_template("index.html", b=banner(), result=result, error=error)


@app.route("/patients")
def patients():
    masked = [
        {"id": p["id"], "name": mask_name(p["name"]), "phone": mask_phone(p["phone"]), "ward": p["ward"]}
        for p in PATIENTS
    ]
    audit.info("patient_list_viewed pod=%s count=%d", HOSTNAME, len(masked))
    return render_template("patients.html", b=banner(), patients=masked)


@app.route("/health")
def health():
    return jsonify(status="UP", version=APP_VERSION, color=APP_COLOR, pod=HOSTNAME, release=RELEASE_NOTE)


@app.route("/api/info")
def info():
    return jsonify(banner() | {"time": datetime.now(timezone.utc).isoformat()})


if __name__ == "__main__":
    # Local development only. In containers the app runs under gunicorn.
    app.run(host="127.0.0.1", port=5000)
