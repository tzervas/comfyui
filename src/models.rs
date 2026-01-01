use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Model {
    pub id: i64,
    pub name: String,
    pub registry: String,
    pub version: Option<String>,
    pub size_bytes: Option<u64>,
    pub sha256: Option<String>,
    pub download_url: Option<String>,
    pub local_path: Option<String>,
    pub status: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
pub struct DownloadRequest {
    pub name: String,
    pub registry: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Node {
    pub id: i64,
    pub name: String,
    pub url: String,
    pub capabilities: serde_json::Value,
    pub last_heartbeat: String,
    pub status: String,
}

#[derive(Debug, Deserialize)]
pub struct RegisterPayload {
    pub service: String,
    pub endpoint: String,
    pub capabilities: serde_json::Value,
}

#[derive(Debug, Deserialize)]
pub struct DiscoverQuery {
    pub service: Option<String>,
    pub preferred_capabilities: Option<serde_json::Value>,
}