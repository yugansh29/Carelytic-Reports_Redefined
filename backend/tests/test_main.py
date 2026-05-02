"""API tests — run from `backend/` with: pytest tests -q"""

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client_no_ai(monkeypatch):
    """Force demo LLM paths so tests never call external providers."""
    import main

    monkeypatch.setattr(main, "bedrock_client", None)
    monkeypatch.setattr(main, "openai_client", None)
    monkeypatch.setattr(main, "ENABLE_DEMO_FALLBACKS", True)
    return TestClient(main.app)


def test_health_ok():
    from main import app

    with TestClient(app) as client:
        r = client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "require_auth" in body


def test_ehr_found():
    from main import app

    with TestClient(app) as client:
        r = client.get("/api/ehr/p123")
    assert r.status_code == 200
    assert r.json()["patient_id"] == "p123"


def test_ehr_not_found():
    from main import app

    with TestClient(app) as client:
        r = client.get("/api/ehr/unknown")
    assert r.status_code == 404


def test_generate_soap_demo_fallback(client_no_ai):
    with client_no_ai as client:
        r = client.post(
            "/api/generate-soap",
            json={
                "transcript_text": "Patient says headache.",
                "patient_context": {"patient_id": "x", "name": "Test"},
            },
        )
    assert r.status_code == 200
    data = r.json()
    assert data.get("is_fallback") is True
    assert "subjective" in data


def test_suggest_questions_demo_fallback(client_no_ai):
    with client_no_ai as client:
        r = client.post(
            "/api/suggest-questions",
            json={"transcript_buffer": "Fever and cough.", "chief_complaint": "URI symptoms"},
        )
    assert r.status_code == 200
    assert isinstance(r.json().get("questions"), list)


def test_patient_summary_demo_fallback(client_no_ai):
    with client_no_ai as client:
        r = client.post(
            "/api/patient-summary",
            json={"soap_json": {"subjective": "x", "objective": "y", "assessment": "z", "plan": "p"}},
        )
    assert r.status_code == 200
    assert "summary" in r.json()
