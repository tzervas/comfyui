#!/bin/bash
# Automation script for batch data ingestion into LangChain RAG
# Usage: ./ingest_data.sh /path/to/pdf/directory

if [ $# -eq 0 ]; then
  echo "Usage: $0 <directory_with_pdfs>"
  exit 1
fi

DIR=$1

if [ ! -d "$DIR" ]; then
  echo "Directory $DIR does not exist"
  exit 1
fi

# Find all PDF files
PDFS=$(find "$DIR" -name "*.pdf" -type f)

if [ -z "$PDFS" ]; then
  echo "No PDF files found in $DIR"
  exit 1
fi

# Use curl to upload to LangChain API
for pdf in $PDFS; do
  echo "Ingesting $pdf..."
  curl -X POST "http://localhost:8000/ingest" \
       -F "files=@$pdf" \
       --max-time 300  # 5 min timeout
  if [ $? -ne 0 ]; then
    echo "Failed to ingest $pdf"
  else
    echo "Ingested $pdf successfully"
  fi
done

echo "Ingestion complete."