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

### POST /agent/run
Run a simple multi-agent flow (planner -> optional code execution -> responder).

**Request:**
```json
{
  "prompt": "Compute 19*23",
  "model": "gemma3:1b",
  "allow_code_execution": true
}
```

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
Execute Python code in a locked-down container with time and resource limits.

**Request Body:**
- `text/plain`: raw Python code
- or JSON: `{ "code": "..." }`

**Response:**
```json
{
  "exit_code": 0,
  "duration_ms": 12,
  "stdout": "hello\n",
  "stderr": "",
  "truncated": false
}
```

### GET /
Status check.

### GET /health
Health check.

## ComfyUI API
ComfyUI provides WebSocket API for workflow execution.

Refer to ComfyUI documentation for details.

## LangFlow API
LangFlow provides REST API for flow management.

Refer to LangFlow documentation for details.