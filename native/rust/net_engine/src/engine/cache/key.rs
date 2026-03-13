//! Cache key and normalization helpers.

use super::CACHE_KEY_VERSION;

pub(super) fn build_cache_key(
    method: &str,
    url: &str,
    headers: &[(String, String)],
    body: Option<&[u8]>,
) -> String {
    let normalized_method = method.trim().to_ascii_uppercase();
    let normalized_url = normalize_url(url);
    let normalized_headers = normalize_headers_for_key(headers);
    let body_hash = body.map(stable_hash_hex).unwrap_or_else(|| "-".to_owned());
    let raw_key = format!(
        "{CACHE_KEY_VERSION}|{normalized_method}|{normalized_url}|{normalized_headers}|{body_hash}"
    );
    stable_hash_hex(raw_key.as_bytes())
}

pub(super) fn normalize_headers_for_key(headers: &[(String, String)]) -> String {
    let mut normalized = Vec::new();
    for (name, value) in headers {
        if name.eq_ignore_ascii_case("if-none-match")
            || name.eq_ignore_ascii_case("if-modified-since")
        {
            continue;
        }
        normalized.push((name.to_ascii_lowercase(), value.trim().to_owned()));
    }
    normalized.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    normalized
        .into_iter()
        .map(|(name, value)| format!("{name}:{value}"))
        .collect::<Vec<_>>()
        .join("\n")
}

pub(super) fn normalize_url(raw_url: &str) -> String {
    let trimmed = raw_url.trim();
    let Ok(mut parsed) = reqwest::Url::parse(trimmed) else {
        return trimmed.to_owned();
    };

    parsed.set_fragment(None);
    let mut query_pairs = parsed
        .query_pairs()
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect::<Vec<_>>();

    if !query_pairs.is_empty() {
        query_pairs.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
        let mut serializer = parsed.query_pairs_mut();
        serializer.clear();
        serializer.extend_pairs(
            query_pairs
                .iter()
                .map(|(key, value)| (key.as_str(), value.as_str())),
        );
    }

    parsed.to_string()
}

pub(super) fn sanitize_key(key: &str) -> String {
    let sanitized = key
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
        .collect::<String>();
    if sanitized.is_empty() {
        stable_hash_hex(key.as_bytes())
    } else {
        sanitized
    }
}

fn stable_hash_hex(input: &[u8]) -> String {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in input {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x100000001b3_u64);
    }
    format!("{hash:016x}")
}
