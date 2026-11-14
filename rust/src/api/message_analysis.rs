#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MessageInsight {
    pub category: String,
    pub verification_code: Option<String>,
}

pub fn analyze_messages(bodies: Vec<String>) -> Vec<MessageInsight> {
    bodies.iter().map(|body| analyze(body)).collect()
}

fn analyze(body: &str) -> MessageInsight {
    if body.len() > 65536 {
        return MessageInsight { category: "personal".into(), verification_code: None };
    }
    let lower = body.to_lowercase();
    let verification = ["验证码", "校验码", "动态码", "verification code", "security code", "one-time", "otp"]
        .iter().any(|keyword| lower.contains(keyword));
    let mut candidates = Vec::new();
    let chars: Vec<char> = body.chars().collect();
    let mut index = 0;
    while index < chars.len() {
        if !chars[index].is_ascii_digit() { index += 1; continue; }
        let start = index;
        while index < chars.len() && chars[index].is_ascii_digit() { index += 1; }
        let length = index - start;
        let bounded = (start == 0 || !chars[start - 1].is_ascii_alphanumeric())
            && (index == chars.len() || !chars[index].is_ascii_alphanumeric());
        if bounded && (4..=8).contains(&length) {
            candidates.push(chars[start..index].iter().collect::<String>());
        }
    }
    candidates.sort();
    candidates.dedup();
    let code = if verification && candidates.len() == 1 { candidates.pop() } else { None };
    let category = if verification { "verification" }
        else if ["退订", "优惠", "促销", "unsubscribe"].iter().any(|word| lower.contains(word)) { "promotion" }
        else { "personal" };
    MessageInsight { category: category.to_owned(), verification_code: code }
}

#[flutter_rust_bridge::frb(init)]
pub fn initialize_message_engine() { flutter_rust_bridge::setup_default_user_utils(); }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extracts_only_unambiguous_credentials() {
        assert_eq!(analyze("验证码：123456，五分钟内有效").verification_code.as_deref(), Some("123456"));
        assert_eq!(analyze("验证码 123456，订单 765432").verification_code, None);
        assert_eq!(analyze("订单 123456").verification_code, None);
        assert_eq!(analyze("OTP: 12345678901").verification_code, None);
        assert_eq!(analyze("OTP: A123456B").verification_code, None);
        assert_eq!(analyze(&format!("OTP 123456{}", "x".repeat(65536))).verification_code, None);
    }
    #[test]
    fn preserves_batch_order_and_unicode() {
        let result = analyze_messages(vec!["退订回T".into(), "你好🌿".into(), "Security code 004321".into()]);
        assert_eq!(result[0].category, "promotion");
        assert_eq!(result[1].category, "personal");
        assert_eq!(result[2].verification_code.as_deref(), Some("004321"));
    }
}
