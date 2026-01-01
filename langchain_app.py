from fastapi import FastAPI
import requests
import logging
from datetime import datetime

app = FastAPI()

OLLAMA_URL = "http://192.168.1.208:11434"

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.get("/")
async def root():
    logger.info(f"Audit: Root endpoint accessed at {datetime.now()}")
    return {"message": "Simple LangChain API"}

@app.post("/generate")
async def generate(data: dict):
    try:
        prompt = data.get("prompt", "")
        model = data.get("model", "gemma3:1b")  # Default to CPU-optimized model
        if not prompt:
            logger.warning(f"Audit: Generate called without prompt at {datetime.now()}")
            return {"error": "No prompt provided"}

        logger.info(f"Audit: Generate called with prompt length {len(prompt)}, model {model} at {datetime.now()}")

        # Call Ollama API directly
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "stream": False
            },
            timeout=60  # Increased timeout for CPU inference
        )

        if response.status_code == 200:
            result = response.json()
            logger.info(f"Audit: Generate successful, response length {len(result.get('response', ''))} at {datetime.now()}")
            return {"response": result.get("response", "")}
        else:
            logger.error(f"Audit: Ollama API error {response.status_code} at {datetime.now()}")
            return {"error": f"Ollama API error: {response.status_code}"}

    except Exception as e:
        logger.error(f"Audit: Exception in generate: {str(e)} at {datetime.now()}")
        return {"error": str(e)}