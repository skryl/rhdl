use crate::signal_value::{compute_mask as narrow_mask, SignalValue, SignedSignalValue};

const WIDE256_MAX_BITS: usize = 256;
const WIDE256_LIMBS: usize = 4;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RuntimeValue {
    Narrow(SignalValue),
    Wide256([u64; WIDE256_LIMBS]),
    Wide(Vec<u64>),
}

impl RuntimeValue {
    pub fn zero(width: usize) -> Self {
        if width <= 128 {
            Self::Narrow(0)
        } else if uses_wide256(width) {
            Self::Wide256([0; WIDE256_LIMBS])
        } else {
            Self::Wide(vec![0; limb_count(width)])
        }
    }

    pub fn from_u128(value: SignalValue, width: usize) -> Self {
        if width <= 128 {
            Self::Narrow(value & narrow_mask(width))
        } else if uses_wide256(width) {
            let mut words = [0u64; WIDE256_LIMBS];
            words[0] = value as u64;
            words[1] = (value >> 64) as u64;
            Self::from_limbs_256(words, width)
        } else {
            Self::from_limbs(low_limbs(value, limb_count(width)), width)
        }
    }

    pub fn from_split_words(low: SignalValue, high_words: &[u64], width: usize) -> Self {
        if width <= 128 {
            return Self::from_u128(low, width);
        }

        if uses_wide256(width) {
            let mut words = [0u64; WIDE256_LIMBS];
            words[0] = low as u64;
            words[1] = (low >> 64) as u64;
            if let Some(word) = high_words.get(0) {
                words[2] = *word;
            }
            if let Some(word) = high_words.get(1) {
                words[3] = *word;
            }
            return Self::from_limbs_256(words, width);
        }

        let mut words = low_limbs(low, limb_count(width));
        for (index, word) in high_words.iter().enumerate() {
            let target = index + 2;
            if target >= words.len() {
                break;
            }
            words[target] = *word;
        }
        Self::from_limbs(words, width)
    }

    pub fn from_signed_i128(value: SignedSignalValue, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow((value as SignalValue) & narrow_mask(width));
        }

        if value >= 0 {
            return Self::from_u128(value as SignalValue, width);
        }

        let magnitude = value.unsigned_abs();
        Self::zero(width).sub(&Self::from_u128(magnitude, width), width)
    }

    pub fn from_unsigned_text(text: &str, width: usize) -> Self {
        if width == 0 {
            return Self::zero(0);
        }

        let digits = text.trim().trim_start_matches('+');
        if digits.is_empty() {
            return Self::zero(width);
        }

        let ten = Self::from_u128(10, width);
        digits.chars().fold(Self::zero(width), |acc, ch| {
            let digit = ch
                .to_digit(10)
                .unwrap_or_else(|| panic!("invalid unsigned literal digit: {ch}"));
            acc.mul(&ten, width).add(&Self::from_u128(digit as SignalValue, width), width)
        })
    }

    pub fn from_signed_text(text: &str, width: usize) -> Self {
        let trimmed = text.trim();
        if let Some(stripped) = trimmed.strip_prefix('-') {
            let magnitude = Self::from_unsigned_text(stripped, width);
            Self::zero(width).sub(&magnitude, width)
        } else {
            Self::from_unsigned_text(trimmed, width)
        }
    }

    pub fn low_u128(&self) -> SignalValue {
        match self {
            Self::Narrow(value) => *value,
            Self::Wide256(words) => {
                let lo = words[0] as SignalValue;
                let hi = words[1] as SignalValue;
                lo | (hi << 64)
            }
            Self::Wide(words) => {
                let lo = words.get(0).copied().unwrap_or(0) as SignalValue;
                let hi = words.get(1).copied().unwrap_or(0) as SignalValue;
                lo | (hi << 64)
            }
        }
    }

    pub fn high_words(&self, width: usize) -> Vec<u64> {
        if width <= 128 {
            return Vec::new();
        }

        match self {
            Self::Narrow(_) => vec![0; limb_count(width).saturating_sub(2)],
            Self::Wide256(words) => {
                let count = limb_count(width);
                if count <= 2 {
                    Vec::new()
                } else {
                    words[2..count].to_vec()
                }
            }
            Self::Wide(words) => {
                let mut out = words.clone();
                out.resize(limb_count(width), 0);
                if out.len() <= 2 {
                    Vec::new()
                } else {
                    out[2..].to_vec()
                }
            }
        }
    }

    pub fn is_zero(&self) -> bool {
        match self {
            Self::Narrow(value) => *value == 0,
            Self::Wide256(words) => words.iter().all(|word| *word == 0),
            Self::Wide(words) => words.iter().all(|word| *word == 0),
        }
    }

    pub fn mask(self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow(self.low_u128() & narrow_mask(width));
        }

        if uses_wide256(width) {
            let mut words = self.to_words4();
            let count = limb_count(width);
            for word in words.iter_mut().skip(count) {
                *word = 0;
            }
            words[count - 1] &= last_word_mask(width);
            return Self::from_limbs_256(words, width);
        }

        let mut words = self.to_words(width);
        words.truncate(limb_count(width));
        if let Some(last) = words.last_mut() {
            *last &= last_word_mask(width);
        }
        Self::from_limbs(words, width)
    }

    pub fn bitand(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow((self.low_u128() & rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);
            for index in 0..count {
                words[index] = a[index] & b[index];
            }
            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let words = a.iter().zip(b.iter()).map(|(lhs, rhs)| lhs & rhs).collect();
        Self::from_limbs(words, width)
    }

    pub fn bitor(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow((self.low_u128() | rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);
            for index in 0..count {
                words[index] = a[index] | b[index];
            }
            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let words = a.iter().zip(b.iter()).map(|(lhs, rhs)| lhs | rhs).collect();
        Self::from_limbs(words, width)
    }

    pub fn bitxor(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow((self.low_u128() ^ rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);
            for index in 0..count {
                words[index] = a[index] ^ b[index];
            }
            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let words = a.iter().zip(b.iter()).map(|(lhs, rhs)| lhs ^ rhs).collect();
        Self::from_limbs(words, width)
    }

    pub fn add(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow(self.low_u128().wrapping_add(rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let mut carry = 0u128;
            let count = limb_count(width);

            for index in 0..count {
                let acc = a[index] as u128 + b[index] as u128 + carry;
                words[index] = acc as u64;
                carry = acc >> 64;
            }

            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let mut words = vec![0u64; limb_count(width)];
        let mut carry = 0u128;

        for index in 0..words.len() {
            let acc = a[index] as u128 + b[index] as u128 + carry;
            words[index] = acc as u64;
            carry = acc >> 64;
        }

        Self::from_limbs(words, width)
    }

    pub fn sub(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow(self.low_u128().wrapping_sub(rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let mut borrow = 0u128;
            let count = limb_count(width);

            for index in 0..count {
                let lhs = a[index] as u128;
                let rhs = b[index] as u128 + borrow;
                if lhs >= rhs {
                    words[index] = (lhs - rhs) as u64;
                    borrow = 0;
                } else {
                    words[index] = ((1u128 << 64) + lhs - rhs) as u64;
                    borrow = 1;
                }
            }

            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let mut words = vec![0u64; limb_count(width)];
        let mut borrow = 0u128;

        for index in 0..words.len() {
            let lhs = a[index] as u128;
            let rhs = b[index] as u128 + borrow;
            if lhs >= rhs {
                words[index] = (lhs - rhs) as u64;
                borrow = 0;
            } else {
                words[index] = ((1u128 << 64) + lhs - rhs) as u64;
                borrow = 1;
            }
        }

        Self::from_limbs(words, width)
    }

    pub fn mul(&self, rhs: &Self, width: usize) -> Self {
        if width <= 128 {
            return Self::Narrow(self.low_u128().wrapping_mul(rhs.low_u128()) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);

            for lhs_index in 0..count {
                let lhs_word = a[lhs_index];
                if lhs_word == 0 {
                    continue;
                }
                let mut carry = 0u128;
                for rhs_index in 0..count {
                    let rhs_word = b[rhs_index];
                    let target = lhs_index + rhs_index;
                    if target >= count {
                        break;
                    }
                    let acc = words[target] as u128 + (lhs_word as u128 * rhs_word as u128) + carry;
                    words[target] = acc as u64;
                    carry = acc >> 64;
                }

                let mut target = lhs_index + count;
                while carry != 0 && target < count {
                    let acc = words[target] as u128 + carry;
                    words[target] = acc as u64;
                    carry = acc >> 64;
                    target += 1;
                }
            }

            return Self::from_limbs_256(words, width);
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        let mut words = vec![0u64; limb_count(width)];

        for (lhs_index, &lhs_word) in a.iter().enumerate() {
            if lhs_word == 0 {
                continue;
            }
            let mut carry = 0u128;
            for (rhs_index, &rhs_word) in b.iter().enumerate() {
                let target = lhs_index + rhs_index;
                if target >= words.len() {
                    break;
                }
                let acc = words[target] as u128 + (lhs_word as u128 * rhs_word as u128) + carry;
                words[target] = acc as u64;
                carry = acc >> 64;
            }

            let mut target = lhs_index + b.len();
            while carry != 0 && target < words.len() {
                let acc = words[target] as u128 + carry;
                words[target] = acc as u64;
                carry = acc >> 64;
                target += 1;
            }
        }

        Self::from_limbs(words, width)
    }

    pub fn shl(&self, shift: usize, width: usize) -> Self {
        if shift >= width {
            return Self::zero(width);
        }

        if width <= 128 {
            return Self::Narrow((self.low_u128() << shift) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let source = self.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);
            let word_shift = shift / 64;
            let bit_shift = shift % 64;

            for (index, &word) in source.iter().enumerate().take(count) {
                if word == 0 {
                    continue;
                }

                let target = index + word_shift;
                if target >= count {
                    break;
                }

                words[target] |= word << bit_shift;
                if bit_shift != 0 && target + 1 < count {
                    words[target + 1] |= word >> (64 - bit_shift);
                }
            }

            return Self::from_limbs_256(words, width);
        }

        let source = self.to_words(width);
        let mut words = vec![0u64; limb_count(width)];
        let word_shift = shift / 64;
        let bit_shift = shift % 64;

        for (index, &word) in source.iter().enumerate() {
            if word == 0 {
                continue;
            }

            let target = index + word_shift;
            if target >= words.len() {
                break;
            }

            words[target] |= word << bit_shift;
            if bit_shift != 0 && target + 1 < words.len() {
                words[target + 1] |= word >> (64 - bit_shift);
            }
        }

        Self::from_limbs(words, width)
    }

    pub fn shr(&self, shift: usize, width: usize) -> Self {
        if shift >= width {
            return Self::zero(width);
        }

        if width <= 128 {
            return Self::Narrow((self.low_u128() >> shift) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let source = self.to_words4();
            let mut words = [0u64; WIDE256_LIMBS];
            let count = limb_count(width);
            let word_shift = shift / 64;
            let bit_shift = shift % 64;

            for target in 0..count {
                let source_index = target + word_shift;
                if source_index >= count {
                    break;
                }

                let mut value = source[source_index] >> bit_shift;
                if bit_shift != 0 && source_index + 1 < count {
                    value |= source[source_index + 1] << (64 - bit_shift);
                }
                words[target] = value;
            }

            return Self::from_limbs_256(words, width);
        }

        let source = self.to_words(width);
        let mut words = vec![0u64; limb_count(width)];
        let word_shift = shift / 64;
        let bit_shift = shift % 64;

        for target in 0..words.len() {
            let source_index = target + word_shift;
            if source_index >= source.len() {
                break;
            }

            let mut value = source[source_index] >> bit_shift;
            if bit_shift != 0 && source_index + 1 < source.len() {
                value |= source[source_index + 1] << (64 - bit_shift);
            }
            words[target] = value;
        }

        Self::from_limbs(words, width)
    }

    pub fn slice(&self, low: usize, width: usize) -> Self {
        self.shr(low, low + width).mask(width)
    }

    pub fn resize(&self, width: usize) -> Self {
        self.clone().mask(width)
    }

    pub fn concat(parts: &[(&RuntimeValue, usize)], width: usize) -> Self {
        let mut result = Self::zero(width);
        for (part, part_width) in parts {
            result = result.shl(*part_width, width);
            result = result.bitor(&(*part).clone().mask(*part_width), width);
        }
        result.mask(width)
    }

    pub fn cmp_unsigned(&self, rhs: &Self, width: usize) -> std::cmp::Ordering {
        if width <= 128 {
            return self.low_u128().cmp(&rhs.low_u128());
        }

        if uses_wide256(width) {
            let a = self.to_words4();
            let b = rhs.to_words4();
            for index in (0..limb_count(width)).rev() {
                match a[index].cmp(&b[index]) {
                    std::cmp::Ordering::Equal => {}
                    other => return other,
                }
            }
            return std::cmp::Ordering::Equal;
        }

        let a = self.to_words(width);
        let b = rhs.to_words(width);
        for index in (0..a.len()).rev() {
            match a[index].cmp(&b[index]) {
                std::cmp::Ordering::Equal => {}
                other => return other,
            }
        }
        std::cmp::Ordering::Equal
    }

    pub fn reduce_and(&self, width: usize) -> bool {
        if width <= 128 {
            return (self.low_u128() & narrow_mask(width)) == narrow_mask(width);
        }

        if uses_wide256(width) {
            let words = self.to_words4();
            let count = limb_count(width);
            for (index, word) in words.iter().enumerate().take(count) {
                let expected = if index + 1 == count {
                    last_word_mask(width)
                } else {
                    u64::MAX
                };
                if *word != expected {
                    return false;
                }
            }
            return true;
        }

        let words = self.to_words(width);
        for (index, word) in words.iter().enumerate() {
            let expected = if index + 1 == words.len() {
                last_word_mask(width)
            } else {
                u64::MAX
            };
            if *word != expected {
                return false;
            }
        }
        true
    }

    pub fn reduce_xor(&self) -> SignalValue {
        match self {
            Self::Narrow(value) => (value.count_ones() as SignalValue) & 1,
            Self::Wide256(words) => (words.iter().map(|word| word.count_ones()).sum::<u32>() as SignalValue) & 1,
            Self::Wide(words) => (words.iter().map(|word| word.count_ones()).sum::<u32>() as SignalValue) & 1,
        }
    }

    pub fn word(&self, width: usize, word_idx: usize) -> u64 {
        if width == 0 || word_idx >= limb_count(width) {
            return 0;
        }

        match self {
            Self::Narrow(value) => {
                if word_idx == 0 {
                    *value as u64
                } else if word_idx == 1 {
                    (*value >> 64) as u64
                } else {
                    0
                }
            }
            Self::Wide256(words) => words[word_idx],
            Self::Wide(words) => words.get(word_idx).copied().unwrap_or(0),
        }
    }

    pub fn with_word(&self, width: usize, word_idx: usize, value: u64) -> Self {
        if width == 0 || word_idx >= limb_count(width) {
            return self.clone();
        }

        if uses_wide256(width) {
            let mut words = self.to_words4();
            words[word_idx] = value;
            return Self::from_limbs_256(words, width);
        }

        let mut words = self.to_words(width);
        if word_idx < words.len() {
            words[word_idx] = value;
        }
        Self::from_limbs(words, width)
    }

    fn to_words(&self, width: usize) -> Vec<u64> {
        let count = limb_count(width);
        let mut words = match self {
            Self::Narrow(value) => low_limbs(*value, count),
            Self::Wide256(words) => words[..count.min(WIDE256_LIMBS)].to_vec(),
            Self::Wide(words) => {
                let mut out = words.clone();
                out.resize(count, 0);
                out
            }
        };
        if let Some(last) = words.last_mut() {
            *last &= last_word_mask(width);
        }
        words
    }

    fn to_words4(&self) -> [u64; WIDE256_LIMBS] {
        match self {
            Self::Narrow(value) => {
                let mut words = [0u64; WIDE256_LIMBS];
                words[0] = *value as u64;
                words[1] = (*value >> 64) as u64;
                words
            }
            Self::Wide256(words) => *words,
            Self::Wide(words) => {
                let mut fixed = [0u64; WIDE256_LIMBS];
                for (index, word) in words.iter().copied().enumerate().take(WIDE256_LIMBS) {
                    fixed[index] = word;
                }
                fixed
            }
        }
    }

    fn from_limbs(mut words: Vec<u64>, width: usize) -> Self {
        if width <= 128 {
            let low = words.get(0).copied().unwrap_or(0) as SignalValue;
            let high = words.get(1).copied().unwrap_or(0) as SignalValue;
            return Self::Narrow((low | (high << 64)) & narrow_mask(width));
        }

        if uses_wide256(width) {
            let mut fixed = [0u64; WIDE256_LIMBS];
            for (index, word) in words.into_iter().enumerate().take(WIDE256_LIMBS) {
                fixed[index] = word;
            }
            return Self::from_limbs_256(fixed, width);
        }

        words.resize(limb_count(width), 0);
        if let Some(last) = words.last_mut() {
            *last &= last_word_mask(width);
        }

        if words.iter().skip(2).all(|word| *word == 0) {
            let low = words.get(0).copied().unwrap_or(0) as SignalValue;
            let high = words.get(1).copied().unwrap_or(0) as SignalValue;
            Self::Narrow(low | (high << 64))
        } else {
            Self::Wide(words)
        }
    }

    fn from_limbs_256(mut words: [u64; WIDE256_LIMBS], width: usize) -> Self {
        let count = limb_count(width);
        for word in words.iter_mut().skip(count) {
            *word = 0;
        }
        words[count - 1] &= last_word_mask(width);

        if words[2] == 0 && words[3] == 0 {
            let low = words[0] as SignalValue;
            let high = words[1] as SignalValue;
            Self::Narrow(low | (high << 64))
        } else {
            Self::Wide256(words)
        }
    }
}

fn limb_count(width: usize) -> usize {
    width.div_ceil(64)
}

fn last_word_mask(width: usize) -> u64 {
    let rem = width % 64;
    if rem == 0 { u64::MAX } else { (1u64 << rem) - 1 }
}

fn low_limbs(value: SignalValue, count: usize) -> Vec<u64> {
    let mut words = vec![0u64; count];
    if count > 0 {
        words[0] = value as u64;
    }
    if count > 1 {
        words[1] = (value >> 64) as u64;
    }
    words
}

fn uses_wide256(width: usize) -> bool {
    width > 128 && width <= WIDE256_MAX_BITS
}
