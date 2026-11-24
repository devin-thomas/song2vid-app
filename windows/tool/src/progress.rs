//! Progress that is always visible (SPEC section 14.5, ADR-018, ADR-019), the Mac command's
//! `CommandProgressDisplay` for Windows.
//!
//! `Snapshot` is the pure part: what a run looks like at one moment and how that is written in
//! each of the three forms. `Display` is the part with a clock: it keeps the latest state and
//! writes it on a timer, so the output keeps moving while FFmpeg has nothing new to say (Checking
//! files, Preparing). `Reporter` is what the command calls as it goes.
//!
//! - **Live**: standard error is a terminal with escape sequences. One line, redrawn every 0.08 s
//!   and replaced by the result at the end.
//! - **Plain**: standard error is not a terminal. A line at each stage change and every second,
//!   with no control characters.
//! - **JSON**: `--json`. JSON Lines on standard output at each stage change and four times a
//!   second; standard error stays empty.
//!
//! Checking files is shown only if it lasts past a short quiet period, so a run that fails at
//! once (a missing file) shows only its error. Every later stage is shown as it begins.

use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::console::Streams;
use crate::json::{JsonKey, JsonValue};

/// How long Checking files is kept quiet.
pub const QUIET_PERIOD: Duration = Duration::from_millis(150);

/// The stages of a run, in order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Stage {
    Checking,
    Preparing,
    Encoding,
    Finishing,
}

impl Stage {
    /// The name in the live and plain lines.
    pub fn title(self) -> &'static str {
        match self {
            Stage::Checking => "Checking files",
            Stage::Preparing => "Preparing",
            Stage::Encoding => "Encoding",
            Stage::Finishing => "Finishing",
        }
    }

    /// The word in JSON.
    pub fn json_name(self) -> &'static str {
        match self {
            Stage::Checking => "checking",
            Stage::Preparing => "preparing",
            Stage::Encoding => "encoding",
            Stage::Finishing => "finishing",
        }
    }
}

/// How a run looks at one moment.
#[derive(Clone, Debug, PartialEq)]
pub struct Snapshot {
    pub stage: Stage,
    /// 0 to 1, or None while it is not known.
    pub fraction: Option<f64>,
    pub elapsed: f64,
    /// Seconds left, or None while it is not known (before encoding has run for a second).
    pub remaining: Option<f64>,
    /// Which frame of the spinner to draw.
    pub tick: usize,
    pub encoder: Option<&'static str>,
}

const SPINNER: [char; 10] = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
const BAR_WIDTH: usize = 16;

/// `m:ss`, with the minutes running past 59.
pub fn clock(seconds: f64) -> String {
    let whole: i64 = (seconds.floor() as i64).max(0);
    format!("{}:{:02}", whole / 60, whole % 60)
}

impl Snapshot {
    fn percent(&self) -> i64 {
        ((self.fraction.unwrap_or(0.0) * 100.0).floor()) as i64
    }

    fn timing(&self) -> String {
        let spent: String = format!("{} elapsed", clock(self.elapsed));
        if self.fraction.is_none() {
            return spent;
        }
        match self.remaining {
            Some(remaining) => format!("{spent} · about {} left", clock(remaining.ceil())),
            None => format!("{spent} · estimating"),
        }
    }

    /// The one-line display. `columns` limits its length so the line never wraps (a wrapped line
    /// can't be redrawn); a line too long for the terminal is cut and drawn without colour.
    pub fn live_text(&self, columns: usize, color: bool) -> String {
        let limit: usize = columns.saturating_sub(1).max(10);
        let plain: String = self.line(false);
        if plain.chars().count() > limit {
            return plain.chars().take(limit).collect();
        }
        if color {
            self.line(true)
        } else {
            plain
        }
    }

    fn line(&self, color: bool) -> String {
        let paint = |text: &str, code: &str| -> String {
            if color {
                format!("\u{1B}[{code}m{text}\u{1B}[0m")
            } else {
                String::from(text)
            }
        };
        let name: String = paint(&format!("{:<14}", self.stage.title()), "1");
        let middle: String = match self.fraction {
            Some(fraction) => {
                let filled: usize = ((fraction * BAR_WIDTH as f64).floor() as usize).min(BAR_WIDTH);
                let bar: String = "█".repeat(filled) + &"░".repeat(BAR_WIDTH - filled);
                format!("{}  {:>3}%", paint(&bar, "36"), self.percent())
            }
            None => paint(&SPINNER[self.tick % SPINNER.len()].to_string(), "36"),
        };
        format!("{name}  {middle}  {}", paint(&self.timing(), "2"))
    }

    /// A line for a log: no control characters.
    pub fn plain_text(&self) -> String {
        let head: String = if self.fraction.is_none() {
            String::from(self.stage.title())
        } else {
            format!("{} {}%", self.stage.title(), self.percent())
        };
        let detail: String = if self.fraction.is_none() {
            format!("{} elapsed", clock(self.elapsed))
        } else if let Some(remaining) = self.remaining {
            format!(
                "{} elapsed, about {} left",
                clock(self.elapsed),
                clock(remaining.ceil())
            )
        } else {
            format!("{} elapsed, estimating time left", clock(self.elapsed))
        };
        format!("{head} ({detail})")
    }

    /// The `progress` line of SPEC section 14.5.
    pub fn json_value(&self) -> JsonValue {
        let mut fields: Vec<(JsonKey, JsonValue)> = vec![
            (
                JsonKey::Stage,
                JsonValue::String(String::from(self.stage.json_name())),
            ),
            (
                JsonKey::Percent,
                self.fraction
                    .map_or(JsonValue::Null, |fraction: f64| -> JsonValue {
                        JsonValue::Seconds((fraction * 1000.0).floor() / 10.0)
                    }),
            ),
            (JsonKey::ElapsedSeconds, JsonValue::Seconds(self.elapsed)),
            (
                JsonKey::RemainingSeconds,
                self.remaining.map_or(JsonValue::Null, JsonValue::Seconds),
            ),
        ];
        if let Some(encoder) = self.encoder {
            fields.push((JsonKey::Encoder, JsonValue::String(String::from(encoder))));
        }
        JsonValue::line_of_type("progress", fields)
    }
}

/// How progress is drawn for one run.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Style {
    Live { color: bool, clears_line: bool },
    Plain,
    Json,
}

impl Style {
    /// How often the latest state is written.
    fn interval(self) -> Duration {
        match self {
            Style::Live { .. } => Duration::from_millis(80),
            Style::Json => Duration::from_millis(250),
            Style::Plain => Duration::from_secs(1),
        }
    }
}

struct State {
    stage: Stage,
    fraction: Option<f64>,
    encoder: Option<&'static str>,
    encoding_started_at: Option<Instant>,
    ticks: usize,
    visible: bool,
    finished: bool,
    live_width: usize,
}

struct Shared {
    streams: Arc<dyn Streams>,
    style: Style,
    started_at: Instant,
    start_delay: Duration,
    interval: Duration,
    state: Mutex<State>,
    wake: Condvar,
}

/// Writes progress as the run goes. Dropping it without `finish` ends the thread but leaves a
/// live line on screen; the command always calls `finish`.
pub struct Display {
    shared: Arc<Shared>,
    thread: Mutex<Option<JoinHandle<()>>>,
}

impl Display {
    /// A display for a run that starts now.
    pub fn start(style: Style, streams: Arc<dyn Streams>) -> Display {
        Display::start_with(style, streams, QUIET_PERIOD, style.interval())
    }

    pub fn start_with(
        style: Style,
        streams: Arc<dyn Streams>,
        start_delay: Duration,
        interval: Duration,
    ) -> Display {
        let shared: Arc<Shared> = Arc::new(Shared {
            streams,
            style,
            started_at: Instant::now(),
            start_delay,
            interval,
            state: Mutex::new(State {
                stage: Stage::Checking,
                fraction: None,
                encoder: None,
                encoding_started_at: None,
                ticks: 0,
                visible: false,
                finished: false,
                live_width: 0,
            }),
            wake: Condvar::new(),
        });
        let worker: Arc<Shared> = Arc::clone(&shared);
        let handle: Option<JoinHandle<()>> = thread::Builder::new()
            .name(String::from("song2vid-progress"))
            .spawn(move || -> () { worker.beat_loop() })
            .ok();
        Display {
            shared,
            thread: Mutex::new(handle),
        }
    }

    /// The display for this run, chosen from where the output is going and the environment.
    pub fn choose(
        json: bool,
        streams: Arc<dyn Streams>,
        no_color: bool,
        dumb_terminal: bool,
    ) -> Display {
        let style: Style = if json {
            Style::Json
        } else if streams.live_columns().is_some() {
            Style::Live {
                color: !dumb_terminal && !no_color,
                clears_line: !dumb_terminal,
            }
        } else {
            Style::Plain
        };
        Display::start(style, streams)
    }

    /// Records a stage and the fraction, if there is one.
    pub fn event(&self, stage: Stage, fraction: Option<f64>, encoder: Option<&'static str>) -> () {
        let mut state: MutexGuard<State> = self.shared.lock();
        if state.finished {
            return;
        }
        let changed: bool = stage != state.stage;
        state.stage = stage;
        state.encoder = encoder;
        if let Some(value) = fraction {
            state.fraction = Some(state.fraction.unwrap_or(0.0).max(value));
            if state.encoding_started_at.is_none() {
                state.encoding_started_at = Some(Instant::now());
            }
        }
        if changed && stage != Stage::Checking {
            state.visible = true;
        }
        // A new stage is shown at once, except in the live display, which redraws on its own
        // beat anyway.
        let live: bool = matches!(self.shared.style, Style::Live { .. });
        if changed && state.visible && !live {
            self.shared.write(&mut state);
        }
    }

    /// Ends the display. The live line is wiped so the result takes its place; the other forms
    /// have nothing to take back. Nothing is written after this returns.
    pub fn finish(&self) -> () {
        {
            let mut state: MutexGuard<State> = self.shared.lock();
            if state.finished {
                return;
            }
            state.finished = true;
            if state.visible {
                if let Style::Live { clears_line, .. } = self.shared.style {
                    let wipe: String = if clears_line {
                        String::from("\r\u{1B}[K")
                    } else {
                        format!("\r{}\r", " ".repeat(state.live_width))
                    };
                    self.shared.streams.write_error(&wipe);
                }
            }
            state.live_width = 0;
        }
        self.shared.wake.notify_all();
        let handle: Option<JoinHandle<()>> = self.thread.lock().ok().and_then(
            |mut slot: MutexGuard<Option<JoinHandle<()>>>| -> Option<JoinHandle<()>> {
                slot.take()
            },
        );
        if let Some(handle) = handle {
            let _ = handle.join();
        }
    }
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(|poisoned| -> MutexGuard<'_, State> { poisoned.into_inner() })
    }

    /// Writes the latest state on a timer until the display is finished.
    fn beat_loop(&self) -> () {
        let mut next: Instant = self.started_at + self.start_delay;
        let mut state: MutexGuard<State> = self.lock();
        loop {
            if state.finished {
                return;
            }
            let now: Instant = Instant::now();
            if now >= next {
                state.visible = true;
                state.ticks += 1;
                self.write(&mut state);
                next += self.interval;
                if next < now {
                    next = now + self.interval;
                }
            }
            let wait: Duration = next.saturating_duration_since(Instant::now());
            state = match self.wake.wait_timeout(state, wait) {
                Ok((guard, _timeout)) => guard,
                Err(poisoned) => poisoned.into_inner().0,
            };
        }
    }

    /// Writes the current state, with the state locked.
    fn write(&self, state: &mut State) -> () {
        let now: Instant = Instant::now();
        let mut remaining: Option<f64> = None;
        if let (Some(fraction), Some(began)) = (state.fraction, state.encoding_started_at) {
            if fraction > 0.0 {
                let encoding: f64 = now.duration_since(began).as_secs_f64();
                if fraction >= 1.0 {
                    remaining = Some(0.0);
                } else if encoding >= 1.0 {
                    remaining = Some(encoding * (1.0 - fraction) / fraction);
                }
            }
        }
        let snapshot: Snapshot = Snapshot {
            stage: state.stage,
            fraction: state.fraction,
            elapsed: now.duration_since(self.started_at).as_secs_f64(),
            remaining,
            tick: state.ticks,
            encoder: state.encoder,
        };
        match self.style {
            Style::Json => self.streams.write_output(&snapshot.json_value().line()),
            Style::Plain => self
                .streams
                .write_error(&format!("{}\n", snapshot.plain_text())),
            Style::Live { color, clears_line } => {
                let columns: usize = self.streams.live_columns().unwrap_or(80);
                let text: String = snapshot.live_text(columns, color);
                let shown: usize = visible_length(&text);
                // Without the clear-line code (a dumb terminal), blanks cover whatever a longer
                // earlier line left.
                let cover: String = if clears_line {
                    String::from("\u{1B}[K")
                } else {
                    " ".repeat(state.live_width.saturating_sub(shown))
                };
                self.streams.write_error(&format!("\r{text}{cover}"));
                state.live_width = shown;
            }
        }
    }
}

/// The length of a line without its colour codes.
fn visible_length(text: &str) -> usize {
    let mut count: usize = 0;
    let mut in_code: bool = false;
    for character in text.chars() {
        if character == '\u{1B}' {
            in_code = true;
        } else if in_code {
            if character == 'm' {
                in_code = false;
            }
        } else {
            count += 1;
        }
    }
    count
}

/// What the command calls as it goes: a stage with no percent yet, or the encoder's fraction.
/// It sends an event only when the stage or the percent moves on, and nothing after `close`.
pub struct Reporter {
    display: Option<Display>,
    current: Option<Stage>,
    last_fraction: Option<f64>,
    encoder: &'static str,
}

impl Reporter {
    /// A reporter that shows nothing (`--quiet`, `--dry-run`).
    pub fn silent() -> Reporter {
        Reporter {
            display: None,
            current: None,
            last_fraction: None,
            encoder: "",
        }
    }

    pub fn showing(display: Display) -> Reporter {
        Reporter {
            display: Some(display),
            current: None,
            last_fraction: None,
            encoder: "",
        }
    }

    /// Says which Encoder is making the video, for the lines from the encoding stage on.
    pub fn set_encoder(&mut self, encoder: &'static str) -> () {
        self.encoder = encoder;
    }

    /// A stage with no percent yet.
    pub fn stage(&mut self, stage: Stage) -> () {
        if self.current == Some(stage) {
            return;
        }
        self.current = Some(stage);
        let encoder: Option<&'static str> = self.known_encoder(stage);
        if let Some(display) = &self.display {
            display.event(stage, None, encoder);
        }
    }

    /// FFmpeg's fraction (0 to 1). The last 1% is the file being closed and moved, so it is
    /// Finishing.
    pub fn encoding(&mut self, fraction: f64) -> () {
        let fraction: f64 = fraction.clamp(0.0, 1.0);
        let stage: Stage = if fraction >= 0.99 {
            Stage::Finishing
        } else {
            Stage::Encoding
        };
        if self
            .last_fraction
            .is_some_and(|last: f64| -> bool { fraction <= last })
            && self.current == Some(stage)
        {
            return;
        }
        self.last_fraction = Some(fraction);
        self.current = Some(stage);
        let encoder: Option<&'static str> = self.known_encoder(stage);
        if let Some(display) = &self.display {
            display.event(stage, Some(fraction), encoder);
        }
    }

    fn known_encoder(&self, stage: Stage) -> Option<&'static str> {
        if stage >= Stage::Encoding && !self.encoder.is_empty() {
            Some(self.encoder)
        } else {
            None
        }
    }

    /// Ends progress.
    pub fn close(&mut self) -> () {
        if let Some(display) = self.display.take() {
            display.finish();
        }
    }
}

impl Drop for Reporter {
    fn drop(&mut self) -> () {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(
        stage: Stage,
        fraction: Option<f64>,
        remaining: Option<f64>,
        tick: usize,
    ) -> Snapshot {
        Snapshot {
            stage,
            fraction,
            elapsed: 4.2,
            remaining,
            tick,
            encoder: None,
        }
    }

    fn encoding(fraction: f64) -> Snapshot {
        snapshot(Stage::Encoding, Some(fraction), Some(3.1), 0)
    }

    #[test]
    fn clock_times_are_minutes_and_seconds() {
        assert_eq!(clock(0.0), "0:00");
        assert_eq!(clock(4.9), "0:04");
        assert_eq!(clock(75.0), "1:15");
        assert_eq!(clock(3725.0), "62:05");
    }

    #[test]
    fn live_encoding_has_a_bar_the_percent_elapsed_and_time_left() {
        assert_eq!(
            encoding(0.52).live_text(120, false),
            "Encoding        ████████░░░░░░░░   52%  0:04 elapsed · about 0:04 left"
        );
    }

    #[test]
    fn live_before_a_time_left_is_known_it_says_estimating() {
        assert_eq!(
            snapshot(Stage::Encoding, Some(0.02), None, 0).live_text(120, false),
            "Encoding        ░░░░░░░░░░░░░░░░    2%  0:04 elapsed · estimating"
        );
    }

    #[test]
    fn live_with_no_percent_a_spinner_moves_one_step_per_tick() {
        let frames: Vec<String> = (0..10)
            .map(|tick: usize| -> String {
                snapshot(Stage::Preparing, None, None, tick).live_text(120, false)
            })
            .collect();
        let mut distinct: Vec<&String> = frames.iter().collect();
        distinct.sort();
        distinct.dedup();
        assert_eq!(distinct.len(), 10);
        assert_eq!(frames[0], "Preparing       ⠋  0:04 elapsed");
        assert_eq!(
            snapshot(Stage::Checking, None, None, 10).live_text(120, false),
            "Checking files  ⠋  0:04 elapsed"
        );
    }

    #[test]
    fn live_colour_only_when_asked_and_a_narrow_terminal_gets_a_cut_line() {
        assert!(encoding(0.5).live_text(120, true).contains("\u{1B}[36m"));
        assert!(!encoding(0.5).live_text(120, false).contains('\u{1B}'));
        let narrow: String = encoding(0.5).live_text(30, true);
        assert_eq!(narrow.chars().count(), 29);
        assert!(!narrow.contains('\u{1B}'));
    }

    #[test]
    fn plain_is_one_line_with_no_control_characters() {
        assert_eq!(
            encoding(0.52).plain_text(),
            "Encoding 52% (0:04 elapsed, about 0:04 left)"
        );
        assert_eq!(
            snapshot(Stage::Encoding, Some(0.03), None, 0).plain_text(),
            "Encoding 3% (0:04 elapsed, estimating time left)"
        );
        assert_eq!(
            snapshot(Stage::Preparing, None, None, 0).plain_text(),
            "Preparing (0:04 elapsed)"
        );
        assert_eq!(
            snapshot(Stage::Checking, None, None, 0).plain_text(),
            "Checking files (0:04 elapsed)"
        );
        assert_eq!(
            snapshot(Stage::Finishing, Some(1.0), Some(0.0), 0).plain_text(),
            "Finishing 100% (0:04 elapsed, about 0:00 left)"
        );
    }

    #[test]
    fn json_has_the_keys_and_nulls_of_the_contract() {
        assert_eq!(
            encoding(0.52).json_value().line(),
            "{\"api_version\":\"1\",\"type\":\"progress\",\"stage\":\"encoding\",\"percent\":52.0,\"elapsed_seconds\":4.2,\"remaining_seconds\":3.1}\n"
        );
        assert_eq!(
            snapshot(Stage::Preparing, None, None, 0).json_value().line(),
            "{\"api_version\":\"1\",\"type\":\"progress\",\"stage\":\"preparing\",\"percent\":null,\"elapsed_seconds\":4.2,\"remaining_seconds\":null}\n"
        );
        let mut with_encoder: Snapshot = encoding(0.5);
        with_encoder.encoder = Some("software");
        assert!(with_encoder
            .json_value()
            .line()
            .ends_with("\"remaining_seconds\":3.1,\"encoder\":\"software\"}\n"));
    }

    /// Collects what a display writes.
    #[derive(Default)]
    struct Recorder {
        output: Mutex<String>,
        error: Mutex<String>,
        live: bool,
    }

    impl Streams for Recorder {
        fn write_output(&self, text: &str) -> () {
            self.output.lock().unwrap().push_str(text);
        }
        fn write_error(&self, text: &str) -> () {
            self.error.lock().unwrap().push_str(text);
        }
        fn live_columns(&self) -> Option<usize> {
            if self.live {
                Some(100)
            } else {
                None
            }
        }
    }

    fn fast(style: Style, recorder: &Arc<Recorder>) -> Display {
        let streams: Arc<dyn Streams> = recorder.clone();
        Display::start_with(style, streams, Duration::ZERO, Duration::from_millis(20))
    }

    #[test]
    fn a_json_display_writes_only_progress_lines_to_standard_output() {
        let recorder: Arc<Recorder> = Arc::new(Recorder::default());
        let display: Display = fast(Style::Json, &recorder);
        display.event(Stage::Preparing, None, None);
        thread::sleep(Duration::from_millis(100));
        display.event(Stage::Encoding, Some(0.25), Some("software"));
        thread::sleep(Duration::from_millis(100));
        display.finish();
        let written: String = recorder.output.lock().unwrap().clone();
        assert!(recorder.error.lock().unwrap().is_empty());
        let lines: Vec<&str> = written.lines().collect();
        assert!(lines.len() >= 4, "{written}");
        for line in &lines {
            assert!(
                line.starts_with("{\"api_version\":\"1\",\"type\":\"progress\""),
                "{line}"
            );
        }
        assert!(written.contains("\"stage\":\"preparing\""));
        assert!(written.contains("\"stage\":\"encoding\",\"percent\":25.0"));
        assert!(written.contains("\"encoder\":\"software\""));
        // Nothing arrives after finish.
        thread::sleep(Duration::from_millis(80));
        assert_eq!(recorder.output.lock().unwrap().clone(), written);
    }

    #[test]
    fn a_plain_display_writes_lines_without_control_characters() {
        let recorder: Arc<Recorder> = Arc::new(Recorder::default());
        let display: Display = fast(Style::Plain, &recorder);
        display.event(Stage::Preparing, None, None);
        thread::sleep(Duration::from_millis(60));
        display.finish();
        let written: String = recorder.error.lock().unwrap().clone();
        assert!(recorder.output.lock().unwrap().is_empty());
        assert!(written.contains("Preparing ("), "{written}");
        assert!(written
            .chars()
            .all(|character: char| -> bool { character == '\n' || !character.is_control() }));
    }

    #[test]
    fn a_live_display_redraws_one_line_and_wipes_it_at_the_end() {
        let recorder: Arc<Recorder> = Arc::new(Recorder {
            live: true,
            ..Recorder::default()
        });
        let display: Display = fast(
            Style::Live {
                color: false,
                clears_line: true,
            },
            &recorder,
        );
        display.event(Stage::Encoding, Some(0.5), Some("software"));
        thread::sleep(Duration::from_millis(100));
        display.finish();
        let written: String = recorder.error.lock().unwrap().clone();
        assert!(written.starts_with("\rEncoding"), "{written}");
        assert!(written.contains("\u{1B}[K"));
        assert!(written.ends_with("\r\u{1B}[K"), "{written:?}");
        assert!(!written.contains('\n'));
    }

    #[test]
    fn a_run_that_ends_during_the_quiet_period_shows_nothing() {
        let recorder: Arc<Recorder> = Arc::new(Recorder::default());
        let streams: Arc<dyn Streams> = recorder.clone();
        let display: Display = Display::start(Style::Json, streams);
        display.event(Stage::Checking, None, None);
        thread::sleep(Duration::from_millis(30));
        display.finish();
        assert!(recorder.output.lock().unwrap().is_empty());
        assert!(recorder.error.lock().unwrap().is_empty());
    }

    #[test]
    fn the_reporter_sends_an_event_only_when_something_moves() {
        let recorder: Arc<Recorder> = Arc::new(Recorder::default());
        let display: Display = fast(Style::Json, &recorder);
        let mut reporter: Reporter = Reporter::showing(display);
        reporter.set_encoder("software");
        reporter.stage(Stage::Preparing);
        reporter.encoding(0.10);
        reporter.encoding(0.10);
        reporter.encoding(0.995);
        reporter.stage(Stage::Finishing);
        thread::sleep(Duration::from_millis(50));
        reporter.close();
        let written: String = recorder.output.lock().unwrap().clone();
        assert!(
            written.contains("\"stage\":\"finishing\",\"percent\":99.5"),
            "{written}"
        );
        // The stage went in order and never back.
        let order: Vec<&str> = written
            .lines()
            .map(|line: &str| -> &str {
                let start: usize = line.find("\"stage\":\"").unwrap() + 9;
                &line[start..start + line[start..].find('"').unwrap()]
            })
            .collect();
        let mut sorted: Vec<&str> = order.clone();
        let rank = |word: &&str| -> usize {
            ["checking", "preparing", "encoding", "finishing"]
                .iter()
                .position(|candidate: &&str| -> bool { candidate == word })
                .unwrap()
        };
        sorted.sort_by_key(rank);
        assert_eq!(order, sorted);
    }
}
