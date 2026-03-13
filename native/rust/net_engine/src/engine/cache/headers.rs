//! Header-focused helpers used by cache policy and revalidation flows.

pub(super) fn cache_control_directives(headers: &[(String, String)]) -> Vec<String> {
    let mut directives = Vec::new();
    for value in header_values(headers, "cache-control") {
        for directive in value.split(',') {
            let normalized = directive.trim().to_ascii_lowercase();
            if !normalized.is_empty() {
                directives.push(normalized);
            }
        }
    }
    directives
}

pub(super) fn first_header_value<'a>(
    headers: &'a [(String, String)],
    name: &str,
) -> Option<&'a str> {
    headers.iter().find_map(|(header_name, header_value)| {
        if header_name.eq_ignore_ascii_case(name) {
            Some(header_value.as_str())
        } else {
            None
        }
    })
}

pub(super) fn header_values<'a>(headers: &'a [(String, String)], name: &str) -> Vec<&'a str> {
    let mut values = Vec::new();
    for (header_name, header_value) in headers {
        if header_name.eq_ignore_ascii_case(name) {
            values.push(header_value.as_str());
        }
    }
    values
}

pub(super) fn normalize_headers_for_storage(headers: &[(String, String)]) -> Vec<(String, String)> {
    let mut normalized = headers
        .iter()
        .map(|(name, value)| (name.to_ascii_lowercase(), value.trim().to_owned()))
        .collect::<Vec<_>>();
    normalized.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    normalized
}

pub(super) fn merge_headers(
    base_headers: &[(String, String)],
    incoming_headers: &[(String, String)],
) -> Vec<(String, String)> {
    let mut merged = base_headers.to_vec();
    for (incoming_name, incoming_value) in incoming_headers {
        if let Some(existing) = merged
            .iter_mut()
            .find(|(existing_name, _)| existing_name.eq_ignore_ascii_case(incoming_name))
        {
            existing.0 = incoming_name.to_ascii_lowercase();
            existing.1 = incoming_value.clone();
            continue;
        }
        merged.push((incoming_name.to_ascii_lowercase(), incoming_value.clone()));
    }

    merged.sort_by(|left, right| left.0.cmp(&right.0).then_with(|| left.1.cmp(&right.1)));
    merged
}
