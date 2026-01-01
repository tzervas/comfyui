# Troubleshooting Guide

## Common Issues

### Service Won't Start
- Check Docker resources: `docker system df`
- View logs: `./manage.sh logs [service]`
- Restart: `./manage.sh restart`

### Authentication Fails
- Check .htpasswd file format
- Ensure correct username/password
- Restart Nginx: `./manage.sh restart nginx`

### SSL Certificate Errors
- Accept self-signed certificate in browser
- For production, replace with proper certificates

### Ollama Model Not Available
- Check model pull: `./manage.sh logs ollama`
- Wait for download completion
- Verify: `curl http://localhost:8081/ollama/api/tags`

### ComfyUI Nodes Missing
- Check installation logs: `./manage.sh logs comfyui`
- Restart ComfyUI: `./manage.sh restart comfyui`

### RAG Not Working
- Check data ingestion: `./manage.sh logs langchain`
- Verify documents in vectorstore
- Test query: `./query_rag.sh "test"`

### High Resource Usage
- Check limits: `docker stats`
- Adjust in docker-compose.yml
- Restart services

### Backup/Restore Issues
- Ensure services stopped during backup
- Check backup directory permissions
- Use absolute paths for restore

## Health Checks
Run `./manage.sh status` for detailed health information.

## Logs
- All services: `./manage.sh logs`
- Specific service: `./manage.sh logs [service]`
- Follow logs: `./manage.sh logs -f [service]`

## Performance Tuning
- Increase CPU/memory limits in docker-compose.yml
- Use GPU for ComfyUI/Ollama
- Optimize model sizes

## Support
- Check README.md for configuration
- Review docker-compose.yml for settings
- Test with `./test-apis.sh all`