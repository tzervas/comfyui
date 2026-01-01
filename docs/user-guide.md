# User Guide for ComfyUI + Ollama + LangChain/LangFlow Stack

## Overview
This stack provides a complete local AI environment with ComfyUI for generative workflows, Ollama for LLM inference, LangChain for RAG applications, and LangFlow for visual flow building.

## Accessing Services
All services are accessible via the Nginx reverse proxy with basic authentication.

### Authentication
- Default users: admin/admin, user1/pass1, user2/pass2
- Change passwords in `.htpasswd` file

### Service URLs
- ComfyUI: https://localhost:8444/comfyui/
- LangFlow: https://localhost:8444/langflow/
- LangChain API: https://localhost:8444/langchain/docs
- Ollama API: https://localhost:8444/ollama/api/tags

## ComfyUI Usage
ComfyUI is pre-configured with LLM integration nodes.

### Loading Workflows
1. Access ComfyUI UI
2. Click "Load" and select from user/default/workflows/ or user/[username]/workflows/
3. Default workflow includes basic text-to-image pipeline

### Custom Nodes
- ComfyUI-Manager: For installing additional nodes
- ComfyUI-LLM-Party: For LLM integration with Ollama
- ComfyUI-Copilot: AI-assisted workflow building

### User Profiles
Each user has separate workflow directories for personalized setups.

## LangFlow Usage
LangFlow provides visual drag-and-drop interface for building AI flows.

### Creating Flows
1. Access LangFlow UI (login with admin/admin)
2. Create new flow
3. Drag components: Ollama models, vector stores, etc.
4. Connect components to build RAG pipelines

### Sample Flow
A sample RAG flow is pre-loaded for document Q&A.

## LangChain API Usage
LangChain provides REST API for RAG operations.

### Ingesting Documents
```bash
./ingest_data.sh /path/to/documents/
```

### Querying
```bash
./query_rag.sh "Your question here"
```

### API Endpoints
- POST /generate: Generate response with RAG
- GET /docs: Interactive API documentation

## Ollama Usage
Ollama serves LLMs locally.

### Available Models
- tinyllama (text generation)
- nomic-embed-text (embeddings)

### API Usage
```bash
curl -X POST http://localhost:8081/ollama/api/generate \
  -H "Content-Type: application/json" \
  -d '{"model": "tinyllama", "prompt": "Hello"}'
```

## Code Execution
Secure Python code execution environment.

### Usage
```bash
curl -X POST http://localhost:8081/code-executor/ \
  -H "Content-Type: text/plain" \
  -d "print('Hello World')"
```

## Management
Use `./manage.sh` for all operations:

- `./manage.sh start/stop/restart`
- `./manage.sh status` - Health checks
- `./manage.sh logs [service]`
- `./manage.sh backup` - Create backup
- `./manage.sh restore [backup_dir]` - Restore from backup
- `./manage.sh monitor` - Continuous monitoring

## Troubleshooting
- Check service health: `./manage.sh status`
- View logs: `./manage.sh logs [service]`
- Test APIs: `./test-apis.sh all`
- Rigorous validation (ingress/API + CLI): see `docs/validation.md`
- Restart services: `./manage.sh restart`