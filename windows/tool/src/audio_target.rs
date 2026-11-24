//! What the AAC track is written with (SPEC section 6.3), worked out from what the song is.
//!
//! A port of the Mac `AudioTarget`. The Mac asks Apple's encoder what it can do; this table is what
//! that answer is, recorded on a Mac, so both commands write the same sample rate, channel count
//! and bit rate for the same song. FFmpeg's `aac` encoder takes all of these.

use crate::media::AudioStream;

/// The sample rates the Mac's AAC encoder offers up to 48 kHz, lowest first.
const SAMPLE_RATES: [i64; 9] = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000];

/// The highest sample rate written. Sources above it are converted down to it.
const HIGHEST_SAMPLE_RATE: i64 = 48_000;

/// The bit rate asked for (SPEC section 6.3), used whenever the encoder can do it.
const WANTED_BIT_RATE: i64 = 256_000;

/// The highest bit rate the Mac's encoder allows at a sample rate, for mono and for stereo, when
/// that is under the 256 kbps asked for. At 44.1 kHz and above 256 kbps is allowed.
const CEILINGS: [(i64, i64, i64); 7] = [
    (8000, 24_000, 48_000),
    (11025, 32_000, 64_000),
    (12000, 32_000, 64_000),
    (16000, 48_000, 96_000),
    (22050, 64_000, 128_000),
    (24000, 64_000, 128_000),
    (32000, 96_000, 192_000),
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AudioTarget {
    pub sample_rate: i64,
    pub channels: i64,
    pub bit_rate: i64,
}

impl AudioTarget {
    pub fn for_song(song: &AudioStream) -> AudioTarget {
        // The source's rate if AAC has it; otherwise the next one up (so no high frequencies are
        // lost), never above the limit.
        let wanted: i64 = song.sample_rate.min(HIGHEST_SAMPLE_RATE);
        let sample_rate: i64 = SAMPLE_RATES
            .iter()
            .copied()
            .find(|rate: &i64| -> bool { *rate >= wanted })
            .unwrap_or(HIGHEST_SAMPLE_RATE);
        // Mono stays mono and everything else is stereo (more than two channels are mixed down).
        let channels: i64 = if song.channels == 1 { 1 } else { 2 };
        let ceiling: i64 = CEILINGS
            .iter()
            .find(|row: &&(i64, i64, i64)| -> bool { row.0 == sample_rate })
            .map_or(WANTED_BIT_RATE, |row: &(i64, i64, i64)| -> i64 {
                if channels == 1 {
                    row.1
                } else {
                    row.2
                }
            });
        AudioTarget {
            sample_rate,
            channels,
            bit_rate: ceiling.min(WANTED_BIT_RATE),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn song(sample_rate: i64, channels: i64) -> AudioStream {
        AudioStream {
            duration: 1.0,
            sample_rate,
            channels,
            time_base: (1, sample_rate),
            declared_frames: None,
            exact_in_container: true,
        }
    }

    fn target(sample_rate: i64, channels: i64) -> (i64, i64, i64) {
        let found: AudioTarget = AudioTarget::for_song(&song(sample_rate, channels));
        (found.sample_rate, found.channels, found.bit_rate)
    }

    #[test]
    fn rates_the_encoder_has_are_kept_up_to_48_khz() {
        assert_eq!(target(44_100, 2), (44_100, 2, 256_000));
        assert_eq!(target(48_000, 2), (48_000, 2, 256_000));
        assert_eq!(target(44_100, 1), (44_100, 1, 256_000));
        assert_eq!(target(22_050, 1), (22_050, 1, 64_000));
        assert_eq!(target(8_000, 2), (8_000, 2, 48_000));
    }

    #[test]
    fn higher_rates_go_to_48_khz() {
        assert_eq!(target(88_200, 2), (48_000, 2, 256_000));
        assert_eq!(target(96_000, 2), (48_000, 2, 256_000));
        assert_eq!(target(192_000, 1), (48_000, 1, 256_000));
    }

    #[test]
    fn rates_the_encoder_lacks_go_to_the_next_rate_up() {
        assert_eq!(target(37_800, 2), (44_100, 2, 256_000));
        assert_eq!(target(7_350, 2), (8_000, 2, 48_000));
        assert_eq!(target(45_000, 2), (48_000, 2, 256_000));
        assert_eq!(target(10_000, 2), (11_025, 2, 64_000));
    }

    #[test]
    fn below_44_khz_the_highest_allowed_bit_rate_is_used() {
        assert_eq!(target(32_000, 2).2, 192_000);
        assert_eq!(target(32_000, 1).2, 96_000);
        assert_eq!(target(24_000, 2).2, 128_000);
        assert_eq!(target(16_000, 1).2, 48_000);
        assert_eq!(target(12_000, 2).2, 64_000);
        assert_eq!(target(11_025, 1).2, 32_000);
    }

    #[test]
    fn channels_stay_mono_or_become_stereo() {
        assert_eq!(target(44_100, 1).1, 1);
        assert_eq!(target(44_100, 2).1, 2);
        assert_eq!(target(44_100, 6).1, 2);
        assert_eq!(target(44_100, 3).1, 2);
    }
}
