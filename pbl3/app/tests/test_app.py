import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest  # noqa: E402

from app import app, assess_vitals, mask_name, mask_phone  # noqa: E402


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "UP"


def test_home_page(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"Vitals Checker" in r.data


def test_vitals_form(client):
    r = client.post("/", data={"weight": "90", "height": "170", "systolic": "145", "sugar": "130"})
    assert r.status_code == 200
    assert b"High risk" in r.data


def test_invalid_input(client):
    r = client.post("/", data={"weight": "abc", "height": "170", "systolic": "120", "sugar": "90"})
    assert b"valid positive numbers" in r.data


def test_assess_normal():
    out = assess_vitals(65, 172, 115, 90)
    assert out["bmi_category"] == "Normal"
    assert out["risk"] == "Low"


def test_pii_masking():
    assert mask_phone("9876543210") == "XXXXXX3210"
    assert mask_name("Arun Kumar") == "A*** K****"


def test_patients_masked(client):
    r = client.get("/patients")
    assert b"9876543210" not in r.data
    assert b"XXXXXX3210" in r.data


def test_security_headers(client):
    r = client.get("/")
    assert r.headers["X-Frame-Options"] == "DENY"
    assert "Content-Security-Policy" in r.headers
