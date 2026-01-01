mod config;
mod database;
mod handlers;
mod models;
mod storage;

use axum::{
    routing::{get, post},
    Router,
};
use clap::{Parser, Subcommand};
use std::sync::Arc;
use tokio::sync::Mutex;
use tower_http::cors::CorsLayer;

use config::Config;
use database::Database;
use storage::Storage;

#[derive(Parser)]
#[command(name = "model-vault")]
#[command(about = "Secure AI model vault service")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the model vault server
    Serve {
        /// Configuration file path
        #[arg(short, long, default_value = "config/model-vault.yaml")]
        config: String,
    },
    /// Download a model
    Download {
        /// Model name (e.g., tinyllama, llama2:7b)
        model: String,
        /// Registry (ollama, huggingface)
        #[arg(short, long, default_value = "ollama")]
        registry: String,
    },
    /// List available models
    List,
    /// Import a local model
    Import {
        /// Path to local model file
        path: String,
        /// Model name
        name: String,
    },
}

#[derive(Clone)]
pub struct AppState {
    config: Config,
    database: Arc<Mutex<Database>>,
    #[allow(dead_code)]
    storage: Arc<Storage>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Serve { config } => {
            let config = Config::load(&config)?;
            let database = Arc::new(Mutex::new(Database::new(&config.database).await?));
            let storage = Arc::new(Storage::new(config.storage.clone())?);

            let state = AppState {
                config: config.clone(),
                database,
                storage,
            };

            let app = Router::new()
                .route("/health", get(handlers::health))
                .route("/models", get(handlers::list_models))
                .route("/models/download", post(handlers::download_model))
                .route("/models/:id", get(handlers::get_model).delete(handlers::delete_model))
                .route("/files/:name", get(handlers::download_file))
                .route("/register", post(handlers::register_node))
                .route("/discover", get(handlers::discover_nodes))
                .layer(CorsLayer::permissive());

            let addr = format!("{}:{}", config.server.host, config.server.port);
            tracing::info!("Starting model vault server on {}", addr);

            let listener = tokio::net::TcpListener::bind(&addr).await?;
            let app = app.with_state(state);
            axum::serve(listener, app).await?;
        }
        Commands::Download { model, registry } => {
            println!("Downloading model {} from {}", model, registry);
            // TODO: Implement download logic
        }
        Commands::List => {
            println!("Available models:");
            // TODO: Implement list logic
        }
        Commands::Import { path, name } => {
            println!("Importing model {} from {}", name, path);
            // TODO: Implement import logic
        }
    }

    Ok(())
}