#!/bin/bash

# Check if ComfyUI web interface is responding and contains expected content
if curl -f --max-time 10 http://localhost:18188/ | grep -q "ComfyUI"; then
  exit 0
fi

exit 1