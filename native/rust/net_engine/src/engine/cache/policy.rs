//! Cache policy decisions derived from HTTP headers.

use std::time::Duration;

use super::headers::{cache_control_directives, header_values};

pub(super) fn request_disables_cache(headers: &[(String, String)]) -> bool {
    let directives = cache_control_directives(headers);
    if directives
        .iter()
        .any(|directive| directive == "no-cache" || directive == "no-store")
    {
        return true;
    }

    header_values(headers, "pragma")
        .iter()
        .any(|value| value.to_ascii_lowercase().contains("no-cache"))
}

pub(super) fn response_has_no_store(headers: &[(String, String)]) -> bool {
    cache_control_directives(headers)
        .iter()
        .any(|directive| directive == "no-store")
}

pub(super) fn resolve_ttl(headers: &[(String, String)], default_ttl: Duration) -> Duration {
    let directives = cache_control_directives(headers);
    if directives.iter().any(|directive| directive == "no-cache") {
        return Duration::ZERO;
    }

    for directive in directives {
        if let Some(raw_age) = directive.strip_prefix("max-age=") {
            if let Ok(age_seconds) = raw_age.trim().parse::<u64>() {
                return Duration::from_secs(age_seconds);
            }
        }
    }

    default_ttl
}
