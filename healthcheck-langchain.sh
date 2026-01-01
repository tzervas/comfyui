#!/bin/bash

# Check if LangChain API docs are responding
if curl -f --max-time 10 http://localhost:8000/docs | grep -q "FastAPI"; then
  exit 0
fi

exit 1