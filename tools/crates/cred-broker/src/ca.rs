//! The broker's certificate authority. To read a request to api.github.com
//! the broker must answer the sandbox's TLS as api.github.com: it does so
//! with a certificate for that host signed by this CA, which the sandbox
//! trusts (the CA bundle pi-safe mounts over the system one).
//!
//! The CA is created once and kept in the state dir (the key 0600): sandbox
//! bundles built from it stay valid across broker restarts.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use rcgen::{
    BasicConstraints, CertificateParams, DnType, ExtendedKeyUsagePurpose, IsCa, Issuer, KeyPair,
    KeyUsagePurpose,
};
use rustls::ServerConfig;
use rustls::pki_types::{PrivateKeyDer, PrivatePkcs8KeyDer};

pub struct Ca {
    issuer: Issuer<'static, KeyPair>,
    /// Host -> TLS config with its certificate, made on first use.
    hosts: Mutex<HashMap<String, Arc<ServerConfig>>>,
}

impl Ca {
    /// The CA certificate, for the sandbox's bundle.
    pub fn cert_path(dir: &Path) -> PathBuf {
        dir.join("ca.pem")
    }

    fn key_path(dir: &Path) -> PathBuf {
        dir.join("ca-key.pem")
    }

    /// Loads the CA from `dir`, creating it on first start.
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        let (cert, key) = (Self::cert_path(dir), Self::key_path(dir));
        if !cert.exists() || !key.exists() {
            Self::create(&cert, &key)?;
        }
        let key_pair = KeyPair::from_pem(&fs::read_to_string(&key)?)
            .with_context(|| format!("invalid {}", key.display()))?;
        let issuer = Issuer::from_ca_cert_pem(&fs::read_to_string(&cert)?, key_pair)
            .with_context(|| format!("invalid {}", cert.display()))?;
        Ok(Self {
            issuer,
            hosts: Mutex::default(),
        })
    }

    fn create(cert: &Path, key: &Path) -> Result<()> {
        let mut params = CertificateParams::default();
        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params
            .distinguished_name
            .push(DnType::CommonName, "cred-broker CA");
        params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        let key_pair = KeyPair::generate()?;
        let ca = params.self_signed(&key_pair)?;
        // the key first: a cert without its key would be useless
        OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(key)?
            .write_all(key_pair.serialize_pem().as_bytes())?;
        fs::write(cert, ca.pem())?;
        Ok(())
    }

    /// TLS config that presents a certificate for `host`.
    pub fn server_config(&self, host: &str) -> Result<Arc<ServerConfig>> {
        if let Some(c) = self.hosts.lock().unwrap().get(host) {
            return Ok(c.clone());
        }
        let mut params = CertificateParams::new(vec![host.to_string()])?;
        params.distinguished_name.push(DnType::CommonName, host);
        params.extended_key_usages = vec![ExtendedKeyUsagePurpose::ServerAuth];
        let key_pair = KeyPair::generate()?;
        let cert = params.signed_by(&key_pair, &self.issuer)?;
        let key = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key_pair.serialize_der()));

        let mut config =
            ServerConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
                .with_safe_default_protocol_versions()?
                .with_no_client_auth()
                .with_single_cert(vec![cert.der().clone()], key)?;
        // HTTP/1.1 only, also when the client offers h2: one protocol to
        // proxy, and every client here speaks it
        config.alpn_protocols = vec![b"http/1.1".to_vec()];

        let config = Arc::new(config);
        self.hosts
            .lock()
            .unwrap()
            .insert(host.to_string(), config.clone());
        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn created_once_then_reused() {
        let dir = crate::test_dir("ca");
        Ca::load_or_create(&dir).unwrap();
        let first = fs::read_to_string(Ca::cert_path(&dir)).unwrap();
        let ca = Ca::load_or_create(&dir).unwrap();
        assert_eq!(fs::read_to_string(Ca::cert_path(&dir)).unwrap(), first);
        let mode = fs::metadata(Ca::key_path(&dir)).unwrap().permissions();
        assert_eq!(
            std::os::unix::fs::PermissionsExt::mode(&mode) & 0o777,
            0o600
        );
        // one config per host, cached
        let a = ca.server_config("api.github.com").unwrap();
        assert!(Arc::ptr_eq(
            &a,
            &ca.server_config("api.github.com").unwrap()
        ));
        fs::remove_dir_all(dir).unwrap();
    }
}
