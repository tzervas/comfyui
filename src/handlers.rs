use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::Json,
    response::IntoResponse,
};
use serde_json::json;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::{models::Model, AppState};

pub async fn health() -> impl IntoResponse {
    Json(json!({ "status": "healthy" }))
}

pub async fn list_models(
    State(state): State<AppState>,
) -> Result<Json<Vec<Model>>, StatusCode> {
    let database = state.database.lock().await;
    match database.list_models().await {
        Ok(models) => Ok(Json(models)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn get_model(
    Path(id): Path<i64>,
    State(state): State<AppState>,
) -> Result<Json<Model>, StatusCode> {
    let database = state.database.lock().await;
    match database.get_model(id).await {
        Ok(Some(model)) => Ok(Json(model)),
        Ok(None) => Err(StatusCode::NOT_FOUND),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn download_model(
    State(state): State<AppState>,
    Json(request): Json<crate::models::DownloadRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
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
    Path(id): Path<i64>,
    State(state): State<AppState>,
) -> Result<StatusCode, StatusCode> {
    // TODO: Implement delete logic
    tracing::info!("Delete request for model id: {}", id);
    Ok(StatusCode::NO_CONTENT)
}

pub async fn download_file(
    Path(name): Path<String>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    // TODO: Implement file serving
    (StatusCode::NOT_IMPLEMENTED, "File serving not implemented")
}

use axum::extract::Query;

pub async fn register_node(
    State(state): State<AppState>,
    Json(payload): Json<crate::models::RegisterPayload>,
) -> Result<StatusCode, StatusCode> {
    let database = state.database.lock().await;
    // TODO: Validate secret header
    // For now, assume validated
    match database.register_node(&payload.service, &payload.endpoint, &payload.capabilities).await {
        Ok(_) => Ok(StatusCode::CREATED),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn discover_nodes(
    Query(query): Query<crate::models::DiscoverQuery>,
    State(state): State<AppState>,
) -> Result<Json<Vec<crate::models::Node>>, StatusCode> {
    let database = state.database.lock().await;
    match database.discover_nodes(query.service.as_deref(), query.preferred_capabilities).await {
        Ok(nodes) => Ok(Json(nodes)),
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}