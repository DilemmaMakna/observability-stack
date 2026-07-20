import logging
import time
import uuid
from typing import Dict, List, Any
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pythonjsonlogger import jsonlogger
from prometheus_fastapi_instrumentator import Instrumentator

# Initialize FastAPI Application
app = FastAPI(title="Lemma AI Service")

# Instrument Application to Expose /metrics
Instrumentator().instrument(app).expose(app)

# Setup Structured JSON Logging
logger = logging.getLogger("lemma-ai-service")
logger.setLevel(logging.INFO)
log_handler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter(
    "%(timestamp)s %(level)s %(service)s %(message)s"
)
log_handler.setFormatter(formatter)
logger.addHandler(log_handler)

# Request Models
class ChatRequest(BaseModel):
    prompt: str
    model: str = "gpt-5.4-mini"

# Mock Database for RAG
KNOWLEDGE_BASE = {
    "observability": "Observability in control theory is a measure of how well internal states of a system can be inferred from knowledge of its external outputs.",
    "loki": "Grafana Loki is a horizontally scalable, highly available, multi-tenant log aggregation system inspired by Prometheus.",
    "prometheus": "Prometheus is a free software application used for event monitoring and alerting. It records real-time metrics in a time-series database."
}

# Function: Simulate Vector DB Retrieval (RAG)
def retrieve_documents(query: str) -> List[str]:
    retrieved = []
    for key, value in KNOWLEDGE_BASE.items():
        if key in query.lower():
            retrieved.append(value)
    return retrieved

# Function: Simulate AI Tool Calling
def execute_tool_call(tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    if tool_name == "fetch_system_status":
        return {"status": "healthy", "uptime_seconds": 3600}
    return {"error": "unknown tool"}

# Endpoint: Chat Simulation
@app.post("/api/chat")
async def chat(request: ChatRequest):
    start_time = time.time()
    trace_id = str(uuid.uuid4())
    
    # 1. RAG Stage (Document Retrieval)
    retrieved_docs = retrieve_documents(request.prompt)
    
    # 2. Tool Calling Stage (Simulated)
    tool_calls = []
    if "status" in request.prompt.lower():
        tool_calls.append({
            "name": "fetch_system_status",
            "arguments": {}
        })
        tool_result = execute_tool_call("fetch_system_status", {})
    else:
        tool_result = None
        
    # 3. LLM Completion Simulation
    duration = time.time() - start_time
    prompt_tokens = len(request.prompt.split()) * 2
    completion_tokens = 50  # Simulated length
    total_tokens = prompt_tokens + completion_tokens
    
    # Construct Response
    response_text = f"Simulated response based on {len(retrieved_docs)} documents retrieved."
    if tool_result:
        response_text += f" Tool execution result: {tool_result}"

    # Log AI Transaction (Structured JSON for Promtail/Loki Ingestion)
    logger.info(
        "AI transaction completed",
        extra={
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "level": "INFO",
            "service": "ai-service",
            "trace_id": trace_id,
            "gen_ai.response.model": request.model,
            "gen_ai.usage.prompt_tokens": prompt_tokens,
            "gen_ai.usage.completion_tokens": completion_tokens,
            "gen_ai.usage.total_tokens": total_tokens,
            "gen_ai.latency_seconds": duration,
            "gen_ai.rag.documents": retrieved_docs,
            "gen_ai.tool_calls": tool_calls
        }
    )
    
    return {
        "trace_id": trace_id,
        "response": response_text,
        "duration_seconds": duration,
        "tokens": {
            "total": total_tokens,
            "prompt": prompt_tokens,
            "completion": completion_tokens
        }
    }

# Endpoint: Health Check
@app.get("/health")
async def health():
    return {"status": "up"}
