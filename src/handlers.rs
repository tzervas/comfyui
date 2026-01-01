use axum::{
    extract::{Path, State},
    http::StatusCode,
    http::HeaderMap,
    response::Json,
    response::IntoResponse,
};
use serde_json::json;

use crate::{models::Model, AppState};

fn validate_vault_token(headers: &HeaderMap, state: &AppState) -> Result<(), StatusCode> {
    let expected = state.config.server.auth_token.trim();
    if expected.is_empty() {
        return Ok(());
    }

    // Prefer Authorization: Bearer <token>
    if let Some(auth) = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok()) {
        if let Some(token) = auth.strip_prefix("Bearer ") {
            if token == expected {
                return Ok(());
            }
        }
    }

    // Fallback header for simple clients
    let provided = headers
        .get("X-Model-Vault-Token")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if provided == expected {
        Ok(())
    } else {
        Err(StatusCode::UNAUTHORIZED)
    }
}

pub async fn health() -> impl IntoResponse {
    Json(json!({ "status": "healthy" }))
}

pub async fn list_models(
    headers: HeaderMap,
    State(state): State<AppState>,
) -> Result<Json<Vec<Model>>, StatusCode> {
    validate_vault_token(&headers, &state)?;
    let database = state.database.lock().await;
    match database.list_models().await {
        Ok(models) => Ok(Json(models)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn get_model(
    headers: HeaderMap,
    Path(id): Path<i64>,
    State(state): State<AppState>,
) -> Result<Json<Model>, StatusCode> {
    validate_vault_token(&headers, &state)?;
    let database = state.database.lock().await;
    match database.get_model(id).await {
        Ok(Some(model)) => Ok(Json(model)),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn download_model(
    headers: HeaderMap,
    State(state): State<AppState>,
    Json(request): Json<crate::models::DownloadRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Download logic is not yet implemented, but protect endpoint anyway.
    validate_vault_token(&headers, &state)?;

    // For now, just acknowledge the request
    // TODO: Implement actual download logic
    tracing::info!("Download request for model: {} from registry: {}", request.name, request.registry);
    
    Ok(Json(json!({
        "status": "accepted",
        "model": request.name,
        "registry": request.registry,
        "message": "Download initiated"
    })))
}

pub async fn delete_model(
    headers: HeaderMap,
    Path(id): Path<i64>,
    State(state): State<AppState>,
) -> Result<StatusCode, StatusCode> {
    validate_vault_token(&headers, &state)?;
    // TODO: Implement delete logic
    tracing::info!("Delete request for model id: {}", id);
    Ok(StatusCode::NO_CONTENT)
}

pub async fn download_file(
    headers: HeaderMap,
    Path(_name): Path<String>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    if let Err(code) = validate_vault_token(&headers, &state) {
        return (code, "Unauthorized");
    }
    // TODO: Implement file serving
    (StatusCode::NOT_IMPLEMENTED, "File serving not implemented")
}

use axum::extract::Query;

fn validate_registry_secret(headers: &HeaderMap, state: &AppState) -> Result<(), StatusCode> {
    let expected = state.config.server.registry_secret.as_deref();
    if expected.is_none() {
        return Ok(());
    }
    let expected = expected.unwrap();

    let provided = headers
        .get("X-Registry-Secret")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if provided == expected {
        Ok(())
    } else {
        Err(StatusCode::UNAUTHORIZED)
    }
}

pub async fn register_node(
    headers: HeaderMap,
    State(state): State<AppState>,
    Json(payload): Json<crate::models::RegisterPayload>,
) -> Result<StatusCode, StatusCode> {
    let database = state.database.lock().await;
    validate_registry_secret(&headers, &state)?;
    match database.register_node(&payload.service, &payload.endpoint, &payload.capabilities).await {
        Ok(_) => Ok(StatusCode::CREATED),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn discover_nodes(
    headers: HeaderMap,
    Query(query): Query<crate::models::DiscoverQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<crate::models::Node>>, StatusCode> {
    let database = state.database.lock().await;
    validate_registry_secret(&headers, &state)?;
    match database.discover_nodes(query.service.as_deref(), query.preferred_capabilities).await {
        Ok(nodes) => Ok(Json(nodes)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}