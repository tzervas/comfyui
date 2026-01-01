import os
from typing import Any

from fastapi import FastAPI, HTTPException
import requests
import logging
from datetime import datetime

from langchain_ollama import ChatOllama
from langgraph.graph import END, StateGraph
from pydantic import BaseModel

app = FastAPI()

OLLAMA_URL = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434").rstrip("/")
CODE_EXECUTOR_URL = os.getenv("CODE_EXECUTOR_URL", "http://code_executor:5000").rstrip("/")
DEFAULT_MODEL = os.getenv("LANGCHAIN_DEFAULT_MODEL", "gemma3:1b")

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
        model = data.get("model", DEFAULT_MODEL)
        if not prompt:
            logger.warning(f"Audit: Generate called without prompt at {datetime.now()}")
            return {"error": "No prompt provided"}

        logger.info(f"Audit: Generate called with prompt length {len(prompt)}, model {model} at {datetime.now()}")

        # Call Ollama API directly
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=60,
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


class AgentRequest(BaseModel):
    prompt: str
    model: str | None = None
    allow_code_execution: bool = True


class AgentState(BaseModel):
    prompt: str
    model: str
    plan: str | None = None
    code: str | None = None
    code_result: dict[str, Any] | None = None
    answer: str | None = None


def _code_executor_tool(code: str) -> dict[str, Any]:
    resp = requests.post(
        f"{CODE_EXECUTOR_URL}/",
        json={"code": code},
        timeout=10,
    )
    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Code executor error: {resp.status_code} {resp.text}")
    return resp.json()


def _build_agent_graph():
    llm = ChatOllama(model=DEFAULT_MODEL, base_url=OLLAMA_URL)

    def planner(state: AgentState) -> AgentState:
        prompt = (
            "You are a planner agent. Decide whether the user request needs Python execution. "
            "If so, produce ONLY a small Python script in a fenced ```python block. "
            "Also produce a brief plan.\n\n"
            f"User request: {state.prompt}"
        )
        msg = llm.invoke(prompt)
        text = getattr(msg, "content", str(msg))

        extracted_code = None
        if "```python" in text:
            extracted_code = text.split("```python", 1)[1].split("```", 1)[0].strip()

        return AgentState(
            prompt=state.prompt,
            model=state.model,
            plan=text.strip(),
            code=extracted_code,
        )

    def maybe_execute(state: AgentState) -> AgentState:
        if not state.code:
            return state
        result = _code_executor_tool(state.code)
        state.code_result = result
        return state

    def responder(state: AgentState) -> AgentState:
        context = ""
        if state.code_result is not None:
            context = f"\n\nPython execution result: {state.code_result}"
        prompt = (
            "You are a helpful assistant. Use the plan and any execution results to answer. "
            "Be concise and accurate.\n\n"
            f"User request: {state.prompt}\n\nPlan: {state.plan}{context}"
        )
        msg = llm.invoke(prompt)
        state.answer = getattr(msg, "content", str(msg))
        return state

    graph = StateGraph(AgentState)
    graph.add_node("planner", planner)
    graph.add_node("maybe_execute", maybe_execute)
    graph.add_node("responder", responder)

    graph.set_entry_point("planner")
    graph.add_edge("planner", "maybe_execute")
    graph.add_edge("maybe_execute", "responder")
    graph.add_edge("responder", END)
    return graph.compile()


_AGENT = _build_agent_graph()


@app.post("/agent/run")
async def agent_run(req: AgentRequest) -> dict[str, Any]:
    if not req.prompt.strip():
        raise HTTPException(status_code=400, detail="prompt is required")

    model = (req.model or DEFAULT_MODEL).strip()

    # Rebuild LLM instance if a different model is requested.
    # (Keep it simple: compile graph per-request when model differs.)
    if model != DEFAULT_MODEL:
        llm = ChatOllama(model=model, base_url=OLLAMA_URL)

        def planner(state: AgentState) -> AgentState:
            prompt = (
                "You are a planner agent. Decide whether the user request needs Python execution. "
                "If so, produce ONLY a small Python script in a fenced ```python block. "
                "Also produce a brief plan.\n\n"
                f"User request: {state.prompt}"
            )
            msg = llm.invoke(prompt)
            text = getattr(msg, "content", str(msg))
            extracted_code = None
            if "```python" in text:
                extracted_code = text.split("```python", 1)[1].split("```", 1)[0].strip()
            return AgentState(prompt=state.prompt, model=state.model, plan=text.strip(), code=extracted_code)

        def maybe_execute(state: AgentState) -> AgentState:
            if not req.allow_code_execution:
                return state
            if not state.code:
                return state
            state.code_result = _code_executor_tool(state.code)
            return state

        def responder(state: AgentState) -> AgentState:
            context = ""
            if state.code_result is not None:
                context = f"\n\nPython execution result: {state.code_result}"
            prompt = (
                "You are a helpful assistant. Use the plan and any execution results to answer. "
                "Be concise and accurate.\n\n"
                f"User request: {state.prompt}\n\nPlan: {state.plan}{context}"
            )
            msg = llm.invoke(prompt)
            state.answer = getattr(msg, "content", str(msg))
            return state

        g = StateGraph(AgentState)
        g.add_node("planner", planner)
        g.add_node("maybe_execute", maybe_execute)
        g.add_node("responder", responder)
        g.set_entry_point("planner")
        g.add_edge("planner", "maybe_execute")
        g.add_edge("maybe_execute", "responder")
        g.add_edge("responder", END)
        agent = g.compile()
    else:
        agent = _AGENT

    state = AgentState(prompt=req.prompt, model=model)
    out = agent.invoke(state)

    return {
        "model": model,
        "plan": out.plan,
        "code": out.code,
        "code_result": out.code_result,
        "answer": out.answer,
    }