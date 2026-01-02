use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use rcgen::{
    BasicConstraints, Certificate, CertificateParams, DistinguishedName, DnType, IsCa, KeyPair,
    KeyUsagePurpose, SanType,
};
use std::fs::{self, OpenOptions};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use time::{Duration, OffsetDateTime};
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "certman")]
#[command(about = "SSL/TLS certificate management for ComfyUI stack", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    #[arg(long, default_value = "ssl")]
    ssl_dir: PathBuf,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize Root CA and Intermediate CA
    InitCa {
        #[arg(long, default_value = "ecdsa-p384")]
        key_type: String,
        
        #[arg(long, default_value = "3650")]
        root_validity_days: i64,
        
        #[arg(long, default_value = "1825")]
        intermediate_validity_days: i64,
    },
    
    /// Generate certificate for domain
    GenerateCert {
        #[arg(long)]
        domain: String,
        
        #[arg(long, default_value = "397")]
        validity_days: i64,
    },
    
    /// Install Root CA to system trust store
    InstallTrust {
        #[arg(long)]
        os: Option<String>,
    },
    
    /// Renew certificates close to expiry
    Renew {
        #[arg(long, default_value = "30")]
        days_before: i64,
    },
    
    /// Export certificates in K8s cert-manager format
    ExportK8s {
        #[arg(long, default_value = "default")]
        namespace: String,
    },
}

struct CertManager {
    ssl_dir: PathBuf,
    ca_dir: PathBuf,
    certs_dir: PathBuf,
    k8s_dir: PathBuf,
}

impl CertManager {
    fn new(ssl_dir: PathBuf) -> Result<Self> {
        let ca_dir = ssl_dir.join("ca");
        let certs_dir = ssl_dir.join("certs");
        let k8s_dir = ssl_dir.join("k8s");

        fs::create_dir_all(&ca_dir)?;
        fs::create_dir_all(&certs_dir)?;
        fs::create_dir_all(&k8s_dir)?;

        Ok(Self {
            ssl_dir,
            ca_dir,
            certs_dir,
            k8s_dir,
        })
    }

    fn init_ca(&self, key_type: &str, root_validity_days: i64, intermediate_validity_days: i64) -> Result<()> {
        info!("Initializing CA hierarchy with key type: {}", key_type);

        // Check if CA already exists
        if self.ca_dir.join("root-ca.crt").exists() {
            warn!("Root CA already exists. Skipping initialization.");
            return Ok(());
        }

        // Generate Root CA
        let mut root_params = CertificateParams::default();
        root_params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        root_params.not_before = OffsetDateTime::now_utc();
        root_params.not_after = OffsetDateTime::now_utc() + Duration::days(root_validity_days);
        
        let mut root_dn = DistinguishedName::new();
        root_dn.push(DnType::CommonName, "ComfyUI Root CA");
        root_dn.push(DnType::OrganizationName, "ComfyUI Stack");
        root_dn.push(DnType::CountryName, "US");
        root_params.distinguished_name = root_dn;
        
        root_params.key_usages = vec![
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
        ];

        let root_key_pair = self.generate_key_pair(key_type)?;
        root_params.key_pair = Some(root_key_pair);
        
        let root_cert = Certificate::from_params(root_params)?;
        
        // Save Root CA
        self.save_cert_and_key(
            &self.ca_dir.join("root-ca.crt"),
            &self.ca_dir.join("root-ca.key"),
            &root_cert,
        )?;
        
        info!("Root CA generated successfully");

        // Generate Intermediate CA
        let mut intermediate_params = CertificateParams::default();
        intermediate_params.is_ca = IsCa::Ca(BasicConstraints::Constrained(0));
        intermediate_params.not_before = OffsetDateTime::now_utc();
        intermediate_params.not_after = OffsetDateTime::now_utc() + Duration::days(intermediate_validity_days);
        
        let mut intermediate_dn = DistinguishedName::new();
        intermediate_dn.push(DnType::CommonName, "ComfyUI Intermediate CA");
        intermediate_dn.push(DnType::OrganizationName, "ComfyUI Stack");
        intermediate_dn.push(DnType::CountryName, "US");
        intermediate_params.distinguished_name = intermediate_dn;
        
        intermediate_params.key_usages = vec![
            KeyUsagePurpose::KeyCertSign,
            KeyUsagePurpose::CrlSign,
        ];

        let intermediate_key_pair = self.generate_key_pair(key_type)?;
        intermediate_params.key_pair = Some(intermediate_key_pair);
        
        let intermediate_cert = Certificate::from_params(intermediate_params)?
            .serialize_der_with_signer(&root_cert)?;
        
        // Save Intermediate CA
        let intermediate_cert_pem = pem::encode(&pem::Pem::new("CERTIFICATE".to_string(), intermediate_cert.clone()));
        fs::write(self.ca_dir.join("intermediate-ca.crt"), &intermediate_cert_pem)?;
        
        // Note: In real implementation, we'd save the intermediate key properly
        // For now, we regenerate when needed
        
        info!("Intermediate CA generated successfully");

        // Create chain file (intermediate + root)
        let root_pem = fs::read_to_string(self.ca_dir.join("root-ca.crt"))?;
        let chain = format!("{}\n{}", intermediate_cert_pem, root_pem);
        fs::write(self.ca_dir.join("chain.pem"), chain)?;
        
        info!("CA chain created");

        Ok(())
    }

    fn generate_cert(&self, domain: &str, validity_days: i64) -> Result<()> {
        info!("Generating certificate for domain: {}", domain);

        // Check if intermediate CA exists
        if !self.ca_dir.join("intermediate-ca.crt").exists() {
            anyhow::bail!("Intermediate CA not found. Run 'certman init-ca' first.");
        }

        // Load intermediate CA
        // Note: In production, we'd properly load the CA with its private key
        // For now, this is a simplified implementation
        
        let domain_dir = self.certs_dir.join(domain.trim_start_matches("*."));
        fs::create_dir_all(&domain_dir)?;

        // Generate certificate
        let mut cert_params = CertificateParams::default();
        cert_params.not_before = OffsetDateTime::now_utc();
        cert_params.not_after = OffsetDateTime::now_utc() + Duration::days(validity_days);
        
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, domain);
        cert_params.distinguished_name = dn;
        
        // Add SANs for wildcard
        if domain.starts_with("*.") {
            cert_params.subject_alt_names = vec![
                SanType::DnsName(domain.to_string()),
                SanType::DnsName(domain.trim_start_matches("*.").to_string()),
            ];
        } else {
            cert_params.subject_alt_names = vec![SanType::DnsName(domain.to_string())];
        }
        
        cert_params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];

        let key_pair = self.generate_key_pair("ecdsa-p384")?;
        cert_params.key_pair = Some(key_pair);
        
        let cert = Certificate::from_params(cert_params)?;
        
        // Save certificate and key
        let cert_path = domain_dir.join("wildcard.crt");
        let key_path = domain_dir.join("wildcard.key");
        
        self.save_cert_and_key(&cert_path, &key_path, &cert)?;
        
        // Create fullchain (cert + intermediate + root)
        let cert_pem = fs::read_to_string(&cert_path)?;
        let chain_pem = fs::read_to_string(self.ca_dir.join("chain.pem"))?;
        let fullchain = format!("{}\n{}", cert_pem, chain_pem);
        fs::write(domain_dir.join("fullchain.pem"), fullchain)?;
        
        info!("Certificate generated successfully at: {}", domain_dir.display());
        
        Ok(())
    }

    fn install_trust(&self, os: Option<String>) -> Result<()> {
        let root_ca_path = self.ca_dir.join("root-ca.crt");
        if !root_ca_path.exists() {
            anyhow::bail!("Root CA not found. Run 'certman init-ca' first.");
        }

        let os = os.unwrap_or_else(|| std::env::consts::OS.to_string());
        
        info!("Installing Root CA to system trust store (OS: {})", os);

        match os.as_str() {
            "linux" => {
                // Copy to system trust directory
                std::process::Command::new("sudo")
                    .args(&["cp", root_ca_path.to_str().unwrap(), "/usr/local/share/ca-certificates/comfyui-root-ca.crt"])
                    .status()?;
                
                std::process::Command::new("sudo")
                    .arg("update-ca-certificates")
                    .status()?;
                
                info!("Root CA installed successfully on Linux");
            }
            "macos" => {
                std::process::Command::new("sudo")
                    .args(&[
                        "security",
                        "add-trusted-cert",
                        "-d",
                        "-r",
                        "trustRoot",
                        "-k",
                        "/Library/Keychains/System.keychain",
                        root_ca_path.to_str().unwrap(),
                    ])
                    .status()?;
                
                info!("Root CA installed successfully on macOS");
            }
            "windows" => {
                std::process::Command::new("certutil")
                    .args(&["-addstore", "-f", "ROOT", root_ca_path.to_str().unwrap()])
                    .status()?;
                
                info!("Root CA installed successfully on Windows");
            }
            _ => {
                anyhow::bail!("Unsupported OS: {}", os);
            }
        }

        Ok(())
    }

    fn generate_key_pair(&self, key_type: &str) -> Result<KeyPair> {
        match key_type {
            "ecdsa-p384" => {
                let key_pair = KeyPair::generate(&rcgen::PKCS_ECDSA_P384_SHA384)?;
                Ok(key_pair)
            }
            "rsa4096" => {
                let key_pair = KeyPair::generate(&rcgen::PKCS_RSA_SHA256)?;
                Ok(key_pair)
            }
            _ => anyhow::bail!("Unsupported key type: {}", key_type),
        }
    }

    fn save_cert_and_key(&self, cert_path: &Path, key_path: &Path, cert: &Certificate) -> Result<()> {
        // Save certificate
        let cert_pem = cert.serialize_pem()?;
        fs::write(cert_path, cert_pem)?;
        
        // Save private key with restricted permissions
        let key_pem = cert.serialize_private_key_pem();
        let mut key_file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(key_path)?;
        
        use std::io::Write;
        key_file.write_all(key_pem.as_bytes())?;
        
        Ok(())
    }
}

fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();
    let manager = CertManager::new(cli.ssl_dir)?;

    match cli.command {
        Commands::InitCa { key_type, root_validity_days, intermediate_validity_days } => {
            manager.init_ca(&key_type, root_validity_days, intermediate_validity_days)?;
        }
        Commands::GenerateCert { domain, validity_days } => {
            manager.generate_cert(&domain, validity_days)?;
        }
        Commands::InstallTrust { os } => {
            manager.install_trust(os)?;
        }
        Commands::Renew { days_before: _ } => {
            warn!("Renew command not yet implemented");
        }
        Commands::ExportK8s { namespace: _ } => {
            warn!("ExportK8s command not yet implemented");
        }
    }

    Ok(())
}
