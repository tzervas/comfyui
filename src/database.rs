use sqlx::{SqlitePool, Row};
use crate::models::Model;

pub struct Database {
    pool: SqlitePool,
}

impl Database {
    pub async fn new(config: &crate::config::DatabaseConfig) -> Result<Self, sqlx::Error> {
        let pool = SqlitePool::connect(&config.url).await?;
        
        // Create tables
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS models (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                registry TEXT NOT NULL,
                version TEXT,
                size_bytes INTEGER,
                sha256 TEXT,
                download_url TEXT,
                local_path TEXT,
                status TEXT DEFAULT 'pending',
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
            "#
        )
        .execute(&pool)
        .await?;

        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS nodes (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                url TEXT NOT NULL,
                capabilities TEXT NOT NULL,  -- JSON
                last_heartbeat DATETIME DEFAULT CURRENT_TIMESTAMP,
                status TEXT DEFAULT 'active'
            )
            "#
        )
        .execute(&pool)
        .await?;
        
        Ok(Self { pool })
    }
    
    pub async fn list_models(&self) -> Result<Vec<Model>, sqlx::Error> {
        let models = sqlx::query(
            "SELECT id, name, registry, version, size_bytes, sha256, download_url, local_path, status, created_at, updated_at FROM models"
        )
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|row| Model {
            id: row.get(0),
            name: row.get(1),
            registry: row.get(2),
            version: row.get(3),
            size_bytes: row.get::<Option<i64>, _>(4).map(|s| s as u64),
            sha256: row.get(5),
            download_url: row.get(6),
            local_path: row.get(7),
            status: row.get(8),
            created_at: row.get(9),
            updated_at: row.get(10),
        })
        .collect();
        
        Ok(models)
    }
    
    pub async fn get_model(&self, id: i64) -> Result<Option<Model>, sqlx::Error> {
        let row = sqlx::query(
            "SELECT id, name, registry, version, size_bytes, sha256, download_url, local_path, status, created_at, updated_at FROM models WHERE id = ?"
        )
        .bind(id)
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(row.map(|row| Model {
            id: row.get(0),
            name: row.get(1),
            registry: row.get(2),
            version: row.get(3),
            size_bytes: row.get::<Option<i64>, _>(4).map(|s| s as u64),
            sha256: row.get(5),
            download_url: row.get(6),
            local_path: row.get(7),
            status: row.get(8),
            created_at: row.get(9),
            updated_at: row.get(10),
        }))
    }

    pub async fn register_node(&self, name: &str, url: &str, capabilities: &serde_json::Value) -> Result<(), sqlx::Error> {
        sqlx::query(
            "INSERT OR REPLACE INTO nodes (name, url, capabilities, last_heartbeat, status) VALUES (?, ?, ?, CURRENT_TIMESTAMP, 'active')"
        )
        .bind(name)
        .bind(url)
        .bind(capabilities.to_string())
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn discover_nodes(&self, service: Option<&str>, preferred_capabilities: Option<serde_json::Value>) -> Result<Vec<crate::models::Node>, sqlx::Error> {
        let mut query = "SELECT id, name, url, capabilities, last_heartbeat, status FROM nodes WHERE status = 'active'".to_string();
        if let Some(svc) = service {
            query.push_str(&format!(" AND name LIKE '%{}%'", svc));
        }
        // For simplicity, ignore preferred_capabilities for now
        let nodes = sqlx::query(&query)
            .fetch_all(&self.pool)
            .await?
            .into_iter()
            .map(|row| crate::models::Node {
                id: row.get(0),
                name: row.get(1),
                url: row.get(2),
                capabilities: serde_json::from_str(&row.get::<String, _>(3)).unwrap_or(serde_json::Value::Null),
                last_heartbeat: row.get(4),
                status: row.get(5),
            })
            .collect();
        Ok(nodes)
    }
}