//! The library half of aws-session, shared with cred-broker and pi-safe:
//!
//!   config   ~/.aws/config, parsed directly: profiles, source_profile chains
//!   glob     profile name patterns (`*.agent`)
//!   session  the two clocks of a login: SSO token and role credentials

pub mod config;
pub mod glob;
mod log;
pub mod session;
