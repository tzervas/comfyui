use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    pub storage: StorageConfig,
    pub server: ServerConfig,
    #[allow(dead_code)]
    pub models: ModelsConfig,
    #[allow(dead_code)]
    pub security: SecurityConfig,
    pub database: DatabaseConfig,
}

#[derive(Debug, Deserialize, Clone)]
pub struct StorageConfig {
    pub path: String,
    #[allow(dead_code)]
    pub max_size_gb: u64,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
    pub auth_token: String,
    #[serde(default)]
    pub registry_secret: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ModelsConfig {
    #[allow(dead_code)]
    pub registries: Vec<RegistryConfig>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct RegistryConfig {
    #[allow(dead_code)]
    pub name: String,
    #[allow(dead_code)]
    pub url: String,
    #[allow(dead_code)]
    pub priority: u8,
    #[allow(dead_code)]
    pub auth_required: bool,
    #[serde(default)]
    #[allow(dead_code)]
    pub auth_token: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct SecurityConfig {
    #[allow(dead_code)]
    pub vault: SecurityLevel,
    #[allow(dead_code)]
    pub ollama: SecurityLevel,
    #[allow(dead_code)]
    pub huggingface: SecurityLevel,
}

#[derive(Debug, Deserialize, Clone)]
pub struct SecurityLevel {
    #[allow(dead_code)]
    pub level: String,
    #[allow(dead_code)]
    pub encryption: bool,
    #[serde(default)]
    #[allow(dead_code)]
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

        let mut parsed: Self = settings.try_deserialize()?;

        // Back-compat / deployment convenience:
        // - MODEL_VAULT_TOKEN overrides server.auth_token
        // - REGISTRY_SECRET overrides server.registry_secret
        if let Ok(token) = std::env::var("MODEL_VAULT_TOKEN") {
            if !token.trim().is_empty() {
                parsed.server.auth_token = token;
            }
        }
        if let Ok(secret) = std::env::var("REGISTRY_SECRET") {
            if !secret.trim().is_empty() {
                parsed.server.registry_secret = Some(secret);
            }
        }

        Ok(parsed)
    }
}