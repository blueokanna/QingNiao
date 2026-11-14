//! A small, immutable parameter atlas for the GPU sky. No frame-by-frame FFI.
//!
//! 8 x 32 cells, four RGBA texels per cell, 32 x 32 pixels total. Alpha is
//! always opaque so Flutter's image decoding cannot premultiply parameter data.
//! RGB texels encode: position/depth, magnitude/phase/period, drift/phase/tint,
//! and two independent noise seeds/occupancy. Values are normalized by the GPU.

const CELLS: usize = 8 * 32;
const STRIDE: usize = 16;

/// Stable for the same installation seed, independent of message contents.
pub fn create_starfield(seed: u32) -> Vec<u8> {
    let mut rng = SplitMix64(u64::from(seed) ^ 0x534b_595f_4249_5244);
    let mut atlas = vec![255; CELLS * STRIDE];
    for cell in atlas.chunks_exact_mut(STRIDE) {
        let depth = rng.unit();
        let magnitude = rng.unit();
        cell[0] = quantize(rng.unit());
        cell[1] = quantize(rng.unit());
        // Most stars are small and distant; bright foreground points are rare.
        cell[2] = quantize(depth * depth);
        cell[4] = quantize(magnitude * magnitude);
        cell[5] = quantize(rng.unit());
        cell[6] = quantize(rng.unit());
        cell[8] = quantize(0.15 + 0.85 * depth);
        cell[9] = quantize(rng.unit());
        cell[10] = quantize(rng.unit());
        cell[12] = quantize(rng.unit());
        cell[13] = quantize(rng.unit());
        cell[14] = if rng.unit() < 0.72 { 255 } else { 0 };
    }
    atlas
}

fn quantize(value: f64) -> u8 {
    (value * 255.0).round() as u8
}

// Explicit algorithm rather than a platform RNG: reproducible on every target.
// This generator is for visual variation only, never cryptographic material.
struct SplitMix64(u64);
impl SplitMix64 {
    fn unit(&mut self) -> f64 {
        self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
        z ^= z >> 31;
        (z >> 11) as f64 * (1.0 / ((1_u64 << 53) as f64))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn deterministic_and_seeded() {
        assert_eq!(create_starfield(42), create_starfield(42));
        assert_ne!(create_starfield(42), create_starfield(43));
        // A stable prefix catches accidental changes to the format or RNG.
        let mut rng = SplitMix64(0);
        assert_eq!((rng.unit() * 1_000_000.0) as u64, 883310);
    }

    #[test]
    fn bounded_opaque_atlas_with_diverse_independent_stars() {
        for seed in [0, 1, 42, 9031, u32::MAX] {
            let atlas = create_starfield(seed);
            assert_eq!(atlas.len(), 4096);
            assert!(atlas.chunks_exact(4).all(|pixel| pixel[3] == 255));
            let cells: Vec<_> = atlas.chunks_exact(STRIDE).collect();
            let occupied = cells.iter().filter(|c| c[14] == 255).count();
            assert!((140..225).contains(&occupied));
            assert!(cells.iter().filter(|c| c[2] < 128).count() > CELLS / 2);
            assert!(cells.iter().map(|c| (c[0], c[1])).collect::<HashSet<_>>().len() > 240);
            assert!(cells.iter().map(|c| (c[5], c[6])).collect::<HashSet<_>>().len() > 240);
        }
    }
}
