use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    pub storage: StorageConfig,
    pub server: ServerConfig,
    pub models: ModelsConfig,
    pub security: SecurityConfig,
    pub database: DatabaseConfig,
}

#[derive(Debug, Deserialize, Clone)]
pub struct StorageConfig {
    pub path: String,
    pub max_size_gb: u64,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub auth_token: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ModelsConfig {
    pub registries: Vec<RegistryConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RegistryConfig {
    pub name: String,
    pub url: String,
    pub priority: u8,
    pub auth_required: bool,
    #[serde(default)]
    pub auth_token: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct SecurityConfig {
    pub vault: SecurityLevel,
    pub ollama: SecurityLevel,
    pub huggingface: SecurityLevel,
}

#[derive(Debug, Deserialize, Clone)]
pub struct SecurityLevel {
    pub level: String,
    pub encryption: bool,
    #[serde(default)]
    pub verify_signatures: bool,
}

#[derive(Debug, Deserialize, Clone)]
pub struct DatabaseConfig {
    pub url: String,
}

impl Config {
    pub fn load(path: &str) -> Result<Self, config::ConfigError> {
        let settings = config::Config::builder()
            .add_source(config::File::with_name(path))
            .add_source(config::Environment::with_prefix("MODEL_VAULT"))
            .build()?;
        
        settings.try_deserialize()
    }
}