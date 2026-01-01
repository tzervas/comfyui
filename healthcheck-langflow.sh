#!/bin/bash

# Check if LangFlow web interface is responding
if curl -f --max-time 10 http://localhost:7860/ | grep -q "Langflow"; then
  exit 0
fi

exit 1