#!/bin/bash
# Automation script for querying LangChain RAG
# Usage: ./query_rag.sh "Your question here"

if [ $# -eq 0 ]; then
  echo "Usage: $0 \"Your question\""
  exit 1
fi

QUESTION=$1

# Query the API
RESPONSE=$(curl -X POST "http://localhost:8000/query" \
              -H "Content-Type: application/json" \
              -d "{\"question\": \"$QUESTION\"}" \
              --silent)

# Extract answer
ANSWER=$(echo $RESPONSE | jq -r '.answer')

echo "Question: $QUESTION"
echo "Answer: $ANSWER"