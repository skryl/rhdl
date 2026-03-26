use serde::de::Error as _;
use serde::{Deserialize, Deserializer};
use serde_json::Value;

pub type SignalValue = u128;
pub type SignedSignalValue = i128;

pub const MAX_SIGNAL_WIDTH: usize = 128;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct SignalValue128 {
    pub lo: u64,
    pub hi: u64,
}

impl SignalValue128 {
    #[inline]
    pub fn from_value(value: SignalValue) -> Self {
        Self {
            lo: value as u64,
            hi: (value >> 64) as u64,
        }
    }

    #[inline]
    pub fn to_value(self) -> SignalValue {
        (self.lo as SignalValue) | ((self.hi as SignalValue) << 64)
    }
}

#[inline]
pub fn compute_mask(width: usize) -> SignalValue {
    if width == 0 {
        0
    } else if width >= MAX_SIGNAL_WIDTH {
        SignalValue::MAX
    } else {
        (1u128 << width) - 1
    }
}

#[inline]
pub fn mask_value(value: SignalValue, width: usize) -> SignalValue {
    value & compute_mask(width)
}

#[inline]
pub fn mask_signed_value(value: SignedSignalValue, width: usize) -> SignalValue {
    (value as SignalValue) & compute_mask(width)
}

#[inline]
pub fn fits_runtime_width(width: usize) -> bool {
    width <= MAX_SIGNAL_WIDTH
}

pub fn deserialize_signal_value<'de, D>(deserializer: D) -> Result<SignalValue, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    parse_signal_value(&value).map_err(D::Error::custom)
}

pub fn deserialize_optional_signal_value<'de, D>(
    deserializer: D,
) -> Result<Option<SignalValue>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    match value {
        Some(v) => parse_signal_value(&v).map(Some).map_err(D::Error::custom),
        None => Ok(None),
    }
}

pub fn deserialize_signal_values<'de, D>(deserializer: D) -> Result<Vec<SignalValue>, D::Error>
where
    D: Deserializer<'de>,
{
    let values = Vec::<Value>::deserialize(deserializer)?;
    values
        .iter()
        .map(|value| parse_signal_value(value).map_err(D::Error::custom))
        .collect()
}

pub fn deserialize_signed_signal_value<'de, D>(deserializer: D) -> Result<SignedSignalValue, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    parse_signed_signal_value(&value).map_err(D::Error::custom)
}

pub fn deserialize_integer_text<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    integer_text(&value).map_err(D::Error::custom)
}

pub fn parse_signal_value(value: &Value) -> Result<SignalValue, String> {
    let text = integer_text(value)?;
    if let Some(stripped) = text.strip_prefix('-') {
        let signed = stripped
            .parse::<SignalValue>()
            .map_err(|e| format!("Invalid negative signal value {}: {}", text, e))?;
        Ok((0u128).wrapping_sub(signed))
    } else {
        text.parse::<SignalValue>()
            .map_err(|e| format!("Invalid signal value {}: {}", text, e))
    }
}

pub fn parse_signed_signal_value(value: &Value) -> Result<SignedSignalValue, String> {
    let text = integer_text(value)?;
    text.parse::<SignedSignalValue>()
        .map_err(|e| format!("Invalid signed signal value {}: {}", text, e))
}

fn integer_text(value: &Value) -> Result<String, String> {
    match value {
        Value::Null => Ok("0".to_string()),
        Value::Bool(flag) => Ok(if *flag { "1".to_string() } else { "0".to_string() }),
        Value::Number(number) => Ok(number.to_string()),
        Value::String(text) => Ok(text.clone()),
        _ => Err(format!("Expected integer-compatible JSON value, got {}", value)),
    }
}
