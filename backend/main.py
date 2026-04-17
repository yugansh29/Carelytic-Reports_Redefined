from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import uvicorn
import json
import logging
from openai import OpenAI

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logger = logging.getLogger(__name__)

client = None
try:
    if os.getenv("OPENAI_API_KEY"):
        client = OpenAI()
except Exception as e:
    logger.warning("OpenAI not configured")

# Dummy Data Fallbacks
DUMMY_SOAP = {
    "subjective": "Patient reports persistent lower back pain for 3 weeks, worse in morning. No radiating pain. Tried ibuprofen with partial relief.",
    "objective": "BP 128/82, HR 74. Paraspinal muscle tenderness at L4-L5. No neurological deficits.",
    "assessment": "Mechanical lower back pain, likely musculoskeletal. Type 2 diabetes background.",
    "plan": "1. Continue ibuprofen. 2. Refer to physiotherapy. 3. X-ray if no improvement in 4 weeks.",
    "confidence_flags": ["assessment"],
    "is_fallback": True
}

DUMMY_QUESTIONS = [
    "Ask about pain scale 1-10",
    "Any radiation to legs?"
]

DUMMY_SUMMARY = {
    "summary": "What We Found: You have mechanical lower back pain. \nYour Next Steps: Take ibuprofen, go to physiotherapy."
}

DUMMY_EHR = {
    "p123": {
        "patient_id": "p123",
        "name": "Raj Sharma",
        "dob": "1984-03-14",
        "active_problems": ["Type 2 diabetes", "Hypertension", "Chronic lower back pain"],
        "medications": ["Metformin 500mg", "Amlodipine 5mg", "Ibuprofen PRN"],
        "recent_records": [
            {"type": "X-Ray", "date": "2024-01-10", "finding": "Mild degenerative changes L4-S1"},
            {"type": "ECG", "date": "2023-11-05", "finding": "Normal sinus rhythm, 72 bpm"},
            {"type": "BMI", "date": "2024-03-25", "finding": "28.4 kg/m2"}
        ]
    }
}

class SoapRequest(BaseModel):
    transcript_text: str
    patient_context: dict

class QuestionRequest(BaseModel):
    transcript_buffer: str
    chief_complaint: str

class SummaryRequest(BaseModel):
    soap_json: dict

@app.get("/api/ehr/{patient_id}")
async def get_ehr(patient_id: str):
    return DUMMY_EHR.get(patient_id, DUMMY_EHR["p123"])

@app.post("/api/transcribe")
async def transcribe(file: UploadFile = File(...)):
    try:
        if not client:
            raise Exception("No client")
        # Save temp file
        temp_file_path = f"temp_{file.filename}"
        with open(temp_file_path, "wb") as buffer:
            buffer.write(await file.read())
        
        with open(temp_file_path, "rb") as audio_file:
            transcript = client.audio.transcriptions.create(
                model="whisper-1", 
                file=audio_file
            )
        os.remove(temp_file_path)
        return {"transcript": transcript.text, "is_fallback": False}
    except Exception as e:
        logger.error(f"Transcription failed: {e}")
        return {"transcript": "Patient: My back has been hurting for 3 weeks. Doctor: Let's do an X-ray and prescribe some Ibuprofen.", "is_fallback": True}

@app.post("/api/generate-soap")
async def generate_soap(req: SoapRequest):
    try:
        if not client:
            raise Exception("No OpenAI client")

        system_prompt = """You are an expert, board-certified medical scribe. Your task is to analyze a clinical transcript and synthesize it into a highly accurate, professional SOAP note.
CRITICAL RULES:
1. NO HALLUCINATIONS: Only include explicit details.
2. MISSING DATA: Use "Not documented." if missing.
3. CONTEXT INTEGRATION: Use Patient Context.
4. CONFIDENCE FLAGGING: If ambiguous, add section to 'confidence_flags' array.
5. STRICT JSON: Match the schema perfectly. Do not wrap in markdown blocks.
OUTPUT SCHEMA:
{
  "subjective": "...",
  "objective": "...",
  "assessment": "...",
  "plan": "...",
  "confidence_flags": ["..."]
}"""
        user_prompt = f"PATIENT CONTEXT: {json.dumps(req.patient_context)}\nTRANSCRIPT: {req.transcript_text}"

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            response_format={"type": "json_object"},
            temperature=0.1,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ]
        )
        data = json.loads(response.choices[0].message.content)
        data["is_fallback"] = False
        return data
    except Exception as e:
        logger.error(f"LLM generation failed: {e}")
        return DUMMY_SOAP

@app.post("/api/suggest-questions")
async def suggest_questions(req: QuestionRequest):
    try:
        if not client:
            raise Exception("No client")
        system_prompt = "You are a clinical assistant. Identify 1-2 critical unasked questions based on transcript. Output raw JSON array of strings ONLY."
        user_prompt = f"Complaint: {req.chief_complaint}\nTranscript: {req.transcript_buffer}"
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            response_format={"type": "json_object"},
            temperature=0.2,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ]
        )
        content = response.choices[0].message.content
        data = json.loads(content)
        # Because we forced JSON object but asked for an array, it might be {"questions": []}.
        if "questions" in data:
            return {"questions": data["questions"]}
        return {"questions": list(data.values())[0]}
    except Exception as e:
        logger.error(f"Suggest questions failed: {e}")
        return {"questions": DUMMY_QUESTIONS}

@app.post("/api/patient-summary")
async def patient_summary(req: SummaryRequest):
    try:
        if not client:
            raise Exception("No client")
        system_prompt = "Translate Clinical SOAP Note into simple 8th-grade summary with headers 'What We Found' and 'Your Next Steps'."
        user_prompt = f"SOAP: {json.dumps(req.soap_json)}"
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0.3,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ]
        )
        return {"summary": response.choices[0].message.content, "is_fallback": False}
    except Exception as e:
        logger.error(f"Summary failed: {e}")
        return {"summary": DUMMY_SUMMARY["summary"], "is_fallback": True}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
