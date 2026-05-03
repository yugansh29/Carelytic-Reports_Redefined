from collections import defaultdict
from typing import Any, Callable
from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
import os
from dotenv import load_dotenv
import uvicorn
import json
import logging
import io
import re
import time

APP_ENV = os.getenv("APP_ENV", "development").lower()
IS_PRODUCTION = APP_ENV == "production"


def _env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


# Load .env from project root; avoid CWD fallbacks in production.
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", ".env"))
if not IS_PRODUCTION:
    load_dotenv()

ENABLE_DEMO_FALLBACKS = _env_bool("ENABLE_DEMO_FALLBACKS", default=not IS_PRODUCTION)
REQUIRE_AUTH = _env_bool("REQUIRE_AUTH", default=IS_PRODUCTION)
API_BEARER_TOKEN = os.getenv("API_BEARER_TOKEN", "")
RATE_LIMIT_PER_MINUTE = _env_int("RATE_LIMIT_PER_MINUTE", 120)
LLM_MAX_RETRIES = max(1, _env_int("LLM_MAX_RETRIES", 2))
CORS_ALLOW_ORIGINS = [
    origin.strip()
    for origin in os.getenv(
        "CORS_ALLOW_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:3000,http://localhost:5173,http://127.0.0.1:5173,http://localhost:8000,http://127.0.0.1:8000,http://localhost:8080,http://127.0.0.1:8080",
    ).split(",")
    if origin.strip()
]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ALLOW_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

security = HTTPBearer(auto_error=False)
_request_buckets: dict[str, list[float]] = defaultdict(list)

# ── Client Setup ──────────────────────────────────────────────────────────────

# OpenAI (for Whisper transcription + GPT-4o-mini)
openai_client = None
try:
    from openai import OpenAI
    key = os.getenv("OPENAI_API_KEY")
    if key:
        openai_client = OpenAI(api_key=key)
        logger.info("✅ OpenAI client initialised")
    else:
        logger.warning("⚠️  OPENAI_API_KEY not set — transcription will use fallback")
except Exception as e:
    logger.warning(f"OpenAI init failed: {e}")

# AWS Bedrock via Anthropic SDK
bedrock_client = None
try:
    from anthropic import AnthropicBedrock
    aws_key = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret = os.getenv("AWS_SECRET_ACCESS_KEY")
    aws_region = os.getenv("AWS_REGION", "us-east-1")
    if aws_key and aws_secret:
        bedrock_client = AnthropicBedrock(
            aws_access_key=aws_key,
            aws_secret_key=aws_secret,
            aws_region=aws_region,
        )
        logger.info(f"✅ AWS Bedrock client initialised (region: {aws_region})")
    else:
        logger.warning("⚠️  AWS credentials not set — LLM calls will use fallback")
except Exception as e:
    logger.warning(f"Bedrock init failed: {e}")

BEDROCK_MODEL_ID = os.getenv("AWS_BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")

# Remove control characters that are illegal in JSON strings when unescaped.
_INVALID_JSON_CONTROL_CHARS = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F]")


async def require_auth(credentials: HTTPAuthorizationCredentials | None = Depends(security)):
    if not REQUIRE_AUTH:
        return

    if not API_BEARER_TOKEN:
        logger.error("REQUIRE_AUTH is enabled but API_BEARER_TOKEN is not configured")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication misconfigured on server",
        )

    if (
        credentials is None
        or credentials.scheme.lower() != "bearer"
        or credentials.credentials != API_BEARER_TOKEN
    ):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")


@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    if request.url.path.startswith("/api/") and request.url.path != "/api/health":
        client_ip = request.client.host if request.client else "unknown"
        now = time.time()
        window_start = now - 60

        bucket = _request_buckets[client_ip]
        while bucket and bucket[0] < window_start:
            bucket.pop(0)

        if len(bucket) >= RATE_LIMIT_PER_MINUTE:
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={"detail": "Rate limit exceeded"},
            )

        bucket.append(now)

    return await call_next(request)

# ── Dummy Fallbacks ───────────────────────────────────────────────────────────

DUMMY_TRANSCRIPT = (
    "Doctor: Good morning Mr. Sharma, what brings you in today?\n"
    "Patient: My back has been hurting for about three weeks now. It's worst in the morning.\n"
    "Doctor: On a scale of 1 to 10, how bad is the pain?\n"
    "Patient: Around a 6. Ibuprofen helps a little.\n"
    "Doctor: Any pain shooting down your legs?\n"
    "Patient: No, it's mostly in my lower back.\n"
    "Doctor: Let me examine you. Your blood pressure is 128 over 82. I can feel some tenderness at L4-L5.\n"
    "Patient: What does that mean?\n"
    "Doctor: Likely a musculoskeletal issue. I'll refer you to physio and order an X-ray."
)

DUMMY_SOAP = {
    "subjective": "Patient reports persistent lower back pain for 3 weeks, worse in the morning. Rates pain 6/10. Partial relief with ibuprofen. No radiating pain to legs.",
    "objective": "BP 128/82 mmHg. Paraspinal muscle tenderness at L4-L5. No neurological deficits detected.",
    "assessment": "Mechanical lower back pain, likely musculoskeletal in origin. Background of Type 2 diabetes and hypertension.",
    "plan": "1. Continue ibuprofen PRN.\n2. Refer to physiotherapy.\n3. Order lumbar spine X-ray.\n4. Review in 4 weeks.",
    "differential_diagnoses": ["Lumbar strain", "Disc herniation", "Degenerative disc disease"],
    "risk_assessment": "Low risk for cauda equina syndrome. No red flags identified.",
    "confidence_flags": [],
    "is_fallback": True,
}

DUMMY_QUESTIONS = [
    "How is your pain at night — does it wake you up?",
    "Any recent falls or injuries to the back?",
]

DUMMY_SUMMARY = {
    "summary": (
        "What We Found:\nYou have mechanical lower back pain. "
        "This means the muscles and joints in your lower back are strained or inflamed.\n\n"
        "Your Next Steps:\n"
        "• Keep taking ibuprofen as needed for pain relief.\n"
        "• Attend physiotherapy sessions to strengthen your back.\n"
        "• Get an X-ray of your lower back.\n"
        "• Come back to see us in 4 weeks."
    )
}

DUMMY_EHR = {
    "p123": {
        "patient_id": "p123",
        "name": "Raj Sharma",
        "dob": "1984-03-14",
        "active_problems": ["Type 2 diabetes", "Hypertension", "Chronic lower back pain"],
        "medications": ["Metformin 500mg BD", "Amlodipine 5mg OD", "Ibuprofen 400mg PRN"],
        "allergies": ["Penicillin"],
        "recent_records": [
            {"type": "X-Ray", "date": "2024-01-10", "finding": "Mild degenerative changes L4-S1"},
            {"type": "ECG", "date": "2023-11-05", "finding": "Normal sinus rhythm, 72 bpm"},
            {"type": "BMI", "date": "2024-03-25", "finding": "28.4 kg/m²"},
            {"type": "HbA1c", "date": "2024-03-25", "finding": "7.1% — well controlled"},
        ],
    }
}

# ── Request Models ────────────────────────────────────────────────────────────

class SoapRequest(BaseModel):
    transcript_text: str
    patient_context: dict

class QuestionRequest(BaseModel):
    transcript_buffer: str
    chief_complaint: str

class SummaryRequest(BaseModel):
    soap_json: dict

# ── Helper: call Bedrock ──────────────────────────────────────────────────────

def _with_retries(label: str, operation: Callable[[], Any]) -> Any:
    last_error: Exception | None = None
    for attempt in range(1, LLM_MAX_RETRIES + 1):
        try:
            return operation()
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            if attempt < LLM_MAX_RETRIES:
                logger.warning("%s failed (attempt %s/%s)", label, attempt, LLM_MAX_RETRIES)
    assert last_error is not None
    raise last_error


def _bedrock_text(system: str, user: str, max_tokens: int = 2000, prefill: str | None = None) -> str:
    """Call Bedrock and return the raw text response. Raises on failure."""
    messages = [{"role": "user", "content": user}]
    if prefill:
        messages.append({"role": "assistant", "content": prefill})
    response = _with_retries(
        "Bedrock call",
        lambda: bedrock_client.messages.create(
            model=BEDROCK_MODEL_ID,
            max_tokens=max_tokens,
            system=system,
            messages=messages,
        ),
    )
    text = response.content[0].text
    if prefill:
        text = prefill + text
    return text


def _extract_first_json_block(text: str, opening: str) -> str:
    """Extract the first balanced JSON object/array from text."""
    closing = "}" if opening == "{" else "]"
    start = text.find(opening)
    if start == -1:
        return text

    depth = 0
    in_string = False
    escape = False

    for i in range(start, len(text)):
        ch = text[i]
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
        elif ch == opening:
            depth += 1
        elif ch == closing:
            depth -= 1
            if depth == 0:
                return text[start:i + 1]

    return text[start:]


def _parse_model_json(raw: str, expected: str = "object"):
    """Parse model output into JSON with cleanup and tolerant fallbacks."""
    text = (raw or "").strip().strip("`")
    text = text.replace("\ufeff", "")

    opening = "{" if expected == "object" else "["
    text = _extract_first_json_block(text, opening)
    text = _INVALID_JSON_CONTROL_CHARS.sub("", text)

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # strict=False allows unescaped control chars that models sometimes emit in strings.
        return json.loads(text, strict=False)

# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/api/ehr/{patient_id}")
async def get_ehr(patient_id: str, _: None = Depends(require_auth)):
    patient = DUMMY_EHR.get(patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    return patient

@app.post("/api/transcribe")
async def transcribe(file: UploadFile = File(...), _: None = Depends(require_auth)):
    if not openai_client:
        if ENABLE_DEMO_FALLBACKS:
            logger.warning("Transcription skipped: no OpenAI client; returning demo transcript")
            return {"transcript": DUMMY_TRANSCRIPT, "is_fallback": True}
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Transcription service unavailable",
        )
    try:
        audio_bytes = await file.read()
        if not audio_bytes:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty audio payload")

        audio_stream = io.BytesIO(audio_bytes)
        audio_stream.name = file.filename or "audio.wav"
        result = _with_retries(
            "OpenAI transcription",
            lambda: openai_client.audio.transcriptions.create(model="whisper-1", file=audio_stream),
        )
        return {"transcript": result.text, "is_fallback": False}
    except HTTPException:
        raise
    except Exception:
        logger.exception("Transcription failed")
        if ENABLE_DEMO_FALLBACKS:
            return {"transcript": DUMMY_TRANSCRIPT, "is_fallback": True}
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Transcription failed")

@app.post("/api/generate-soap")
async def generate_soap(req: SoapRequest, _: None = Depends(require_auth)):
    system_prompt = """You are an expert, board-certified medical scribe.
Analyse the clinical transcript and synthesise it into a professional, highly precise SOAP note.

RULES:
1. NO HALLUCINATIONS — only include details explicitly present in the transcript.
2. Use clinical terminology (e.g., 'erythematous' instead of 'red').
3. Integrate provided Patient Context (active problems, meds, allergies) into the Subjective/Assessment as relevant.
4. Include a 'differential_diagnoses' array and 'risk_assessment' (e.g., 'Low risk for PE').
5. Output STRICT JSON only.
6. The Objective section MUST be derived from the conversation transcript only (exam findings, vitals, observed signs, measurements, investigations explicitly mentioned).
7. If no objective findings are explicitly present, set Objective to a clear statement that no objective findings were documented and explicitly name the patient's exact presenting problem from the conversation.

OUTPUT SCHEMA:
{
  "subjective": "...",
  "objective": "...",
  "assessment": "...",
  "plan": "...",
  "differential_diagnoses": ["..."],
  "risk_assessment": "...",
  "confidence_flags": []
}"""
    user_prompt = f"PATIENT CONTEXT:\n{json.dumps(req.patient_context, indent=2)}\n\nTRANSCRIPT:\n{req.transcript_text}"

    try:
        if bedrock_client:
            raw = _bedrock_text(system_prompt, user_prompt, max_tokens=2000, prefill="{")
            data = _parse_model_json(raw, expected="object")
        elif openai_client:
            response = _with_retries(
                "OpenAI SOAP generation",
                lambda: openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    response_format={"type": "json_object"},
                    temperature=0.1,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                ),
            )
            data = _parse_model_json(response.choices[0].message.content, expected="object")
        else:
            raise Exception("No AI client available")

        data["is_fallback"] = False
        return data
    except Exception:
        logger.exception("SOAP generation failed")
        if ENABLE_DEMO_FALLBACKS:
            return DUMMY_SOAP
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="SOAP generation failed")

@app.post("/api/suggest-questions")
async def suggest_questions(req: QuestionRequest, _: None = Depends(require_auth)):
    system_prompt = (
        "You are a clinical assistant helping a doctor during a live consultation. "
        "Based on the transcript so far, identify 2–3 critical follow-up questions the doctor should ask. "
        "Return a JSON array of short question strings ONLY. No explanations. Example: [\"Describe the pain character.\", \"Any fever?\"]"
    )
    user_prompt = f"Chief Complaint: {req.chief_complaint}\n\nTranscript so far:\n{req.transcript_buffer}"

    try:
        if bedrock_client:
            raw = _bedrock_text(system_prompt, user_prompt, max_tokens=300, prefill="[")
            questions = _parse_model_json(raw, expected="array")
        elif openai_client:
            response = _with_retries(
                "OpenAI question generation",
                lambda: openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    temperature=0.3,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                        {"role": "assistant", "content": "["},
                    ],
                ),
            )
            raw = "[" + response.choices[0].message.content
            questions = _parse_model_json(raw, expected="array")
        else:
            raise Exception("No AI client")

        # Normalise — model may return list or {"questions": [...]}
        if isinstance(questions, dict):
            nested = questions.get("questions")
            if isinstance(nested, list):
                questions = nested
            else:
                list_values = [v for v in questions.values() if isinstance(v, list)]
                questions = list_values[0] if list_values else []
        if not isinstance(questions, list):
            questions = []
        return {"questions": [str(q) for q in questions]}
    except Exception:
        logger.exception("Suggest questions failed")
        if ENABLE_DEMO_FALLBACKS:
            return {"questions": DUMMY_QUESTIONS}
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Question generation failed")

@app.post("/api/patient-summary")
async def patient_summary(req: SummaryRequest, _: None = Depends(require_auth)):
    system_prompt = (
        "Translate the following clinical SOAP note into a plain-language patient summary at an 8th-grade reading level. "
        "Use exactly two sections with these headers:\n\n"
        "What We Found:\n<explanation>\n\nYour Next Steps:\n<bulleted list>"
    )
    user_prompt = f"SOAP Note:\n{json.dumps(req.soap_json, indent=2)}"

    try:
        if bedrock_client:
            summary_text = _bedrock_text(system_prompt, user_prompt, max_tokens=800)
        elif openai_client:
            response = _with_retries(
                "OpenAI summary generation",
                lambda: openai_client.chat.completions.create(
                    model="gpt-4o-mini",
                    temperature=0.3,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                ),
            )
            summary_text = response.choices[0].message.content
        else:
            raise Exception("No AI client")

        return {"summary": summary_text, "is_fallback": False}
    except Exception:
        logger.exception("Summary failed")
        if ENABLE_DEMO_FALLBACKS:
            return {"summary": DUMMY_SUMMARY["summary"], "is_fallback": True}
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail="Summary generation failed")

@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "environment": APP_ENV,
        "require_auth": REQUIRE_AUTH,
        "rate_limit_per_minute": RATE_LIMIT_PER_MINUTE,
        "openai": openai_client is not None,
        "bedrock": bedrock_client is not None,
        "bedrock_model": BEDROCK_MODEL_ID,
    }

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
