use thiserror::Error;

use crate::api::NetErrorKind;

#[derive(Debug, Error)]
pub enum NetError {
    #[error("timeout: {0}")]
    Timeout(String),

    #[error("dns: {0}")]
    Dns(String),

    #[error("tls: {0}")]
    Tls(String),

    #[error("http {status}: {message}")]
    Http { status: u16, message: String },

    #[error("canceled: {0}")]
    Canceled(String),

    #[error("parse: {0}")]
    Parse(String),

    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("internal: {0}")]
    Internal(String),
}

impl NetError {
    pub fn kind(&self) -> NetErrorKind {
        match self {
            Self::Timeout(_) => NetErrorKind::Timeout,
            Self::Dns(_) => NetErrorKind::Dns,
            Self::Tls(_) => NetErrorKind::Tls,
            Self::Http { status, .. } if *status >= 400 && *status < 500 => NetErrorKind::Http4xx,
            Self::Http { .. } => NetErrorKind::Http5xx,
            Self::Canceled(_) => NetErrorKind::Canceled,
            Self::Parse(_) => NetErrorKind::Parse,
            Self::Io(_) => NetErrorKind::Io,
            Self::Internal(_) => NetErrorKind::Internal,
        }
    }

    /// 从 reqwest::Error 映射到统一错误分类
    pub fn from_reqwest(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            Self::Timeout(e.to_string())
        } else if e.is_connect() {
            Self::Dns(e.to_string())
        } else if let Some(status) = e.status() {
            Self::Http {
                status: status.as_u16(),
                message: e.to_string(),
            }
        } else {
            Self::Internal(e.to_string())
        }
    }

    /// 返回统一错误码字符串，供 Flutter 侧匹配
    pub fn error_code(&self) -> &'static str {
        match self.kind() {
            NetErrorKind::Timeout => "timeout",
            NetErrorKind::Dns => "dns",
            NetErrorKind::Tls => "tls",
            NetErrorKind::Http4xx => "http_4xx",
            NetErrorKind::Http5xx => "http_5xx",
            NetErrorKind::Canceled => "canceled",
            NetErrorKind::Parse => "parse",
            NetErrorKind::Io => "io",
            NetErrorKind::Internal => "internal",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::NetError;
    use crate::api::NetErrorKind;

    #[test]
    fn kind_maps_timeout() {
        assert_eq!(
            NetError::Timeout("slow".into()).kind(),
            NetErrorKind::Timeout
        );
    }

    #[test]
    fn kind_maps_http_family() {
        assert_eq!(
            NetError::Http {
                status: 404,
                message: "missing".into(),
            }
            .kind(),
            NetErrorKind::Http4xx
        );
        assert_eq!(
            NetError::Http {
                status: 503,
                message: "down".into(),
            }
            .kind(),
            NetErrorKind::Http5xx
        );
    }
}
