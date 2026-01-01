use std::path::PathBuf;
use tokio::fs;
use crate::config::StorageConfig;

pub struct Storage {
    #[allow(dead_code)]
    config: StorageConfig,
}

impl Storage {
    pub fn new(config: StorageConfig) -> Result<Self, std::io::Error> {
        // Ensure storage directory exists
        std::fs::create_dir_all(&config.path)?;
        
        Ok(Self { config })
    }
    
    #[allow(dead_code)]
    pub fn get_model_path(&self, model_name: &str) -> PathBuf {
        PathBuf::from(&self.config.path).join("models").join(model_name)
    }
    
    #[allow(dead_code)]
    pub async fn ensure_model_dir(&self, model_name: &str) -> Result<PathBuf, std::io::Error> {
        let path = self.get_model_path(model_name);
        fs::create_dir_all(&path).await?;
        Ok(path)
    }
}