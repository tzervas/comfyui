# API Reference

## LangChain API

### POST /generate
Generate response with RAG context.

**Request:**
```json
{
  "prompt": "What is artificial intelligence?",
  "context_docs": 3
}
```

**Response:**
```json
{
  "response": "AI is...",
  "sources": ["doc1.pdf", "doc2.pdf"]
}
```

### GET /health
Health check endpoint.

## Ollama API

### POST /api/generate
Generate text from LLM.

**Request:**
```json
{
  "model": "tinyllama",
  "prompt": "Hello world",
  "stream": false
}
```

**Response:**
```json
{
  "response": "Hello! How can I help you today?",
  "done": true
}
```

### GET /api/tags
List available models.

**Response:**
```json
{
  "models": [
    {
      "name": "tinyllama:latest",
      "size": "637MB"
    }
  ]
}
```

## Code Executor API

### POST /
Execute Python code.

**Request Body:** Python code as text/plain

**Response:** Execution output

### GET /
Status check.

## ComfyUI API
ComfyUI provides WebSocket API for workflow execution.

Refer to ComfyUI documentation for details.

## LangFlow API
LangFlow provides REST API for flow management.

Refer to LangFlow documentation for details.