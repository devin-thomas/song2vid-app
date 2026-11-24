//! Output frame sizes and image placement (SPEC section 5).
//!
//! This is a port of `OutputFrame` in `Song2VidCore`. The Swift code is the source of truth:
//! `fixtures/frame-math.json`, written by the Swift tests, is the proof that the two agree. Every
//! operation here repeats the Swift operation in the same order, so a floating-point result is the
//! same double, not a nearby one.

/// A size in whole pixels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PixelSize {
    pub width: i64,
    pub height: i64,
}

/// The proportions of the output video.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameShape {
    SixteenByNine,
    NineBySixteen,
    OneByOne,
    FourByThree,
    Original,
}

impl FrameShape {
    /// Every shape, in the order `check` lists them.
    pub const ALL: [FrameShape; 5] = [
        FrameShape::SixteenByNine,
        FrameShape::NineBySixteen,
        FrameShape::OneByOne,
        FrameShape::FourByThree,
        FrameShape::Original,
    ];

    /// The name on the command line and in JSON: `16:9`, `9:16`, `1:1`, `4:3` or `original`.
    pub fn command_name(self) -> &'static str {
        match self {
            FrameShape::SixteenByNine => "16:9",
            FrameShape::NineBySixteen => "9:16",
            FrameShape::OneByOne => "1:1",
            FrameShape::FourByThree => "4:3",
            FrameShape::Original => "original",
        }
    }

    /// The shape for a name on the command line. Names are exact: `ORIGINAL` is not `original`.
    pub fn from_command_name(name: &str) -> Option<FrameShape> {
        FrameShape::ALL
            .into_iter()
            .find(|shape: &FrameShape| -> bool { shape.command_name() == name })
    }
}

/// The size tier of the output video, named by the pixel count of the frame's short side.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Resolution {
    P480,
    P1080,
    P2160,
}

impl Resolution {
    pub const ALL: [Resolution; 3] = [Resolution::P480, Resolution::P1080, Resolution::P2160];

    /// The frame's short side in pixels.
    pub fn short_side(self) -> i64 {
        match self {
            Resolution::P480 => 480,
            Resolution::P1080 => 1080,
            Resolution::P2160 => 2160,
        }
    }

    /// The name on the command line and in JSON: `480p`, `1080p` or `2160p`.
    pub fn command_name(self) -> String {
        format!("{}p", self.short_side())
    }

    pub fn from_command_name(name: &str) -> Option<Resolution> {
        Resolution::ALL
            .into_iter()
            .find(|resolution: &Resolution| -> bool { resolution.command_name() == name })
    }
}

/// Which part of the image a Crop keeps: 0 puts the image's left or top edge against the frame's,
/// 1 the right or bottom edge, and 0.5 is centred. Values past an edge are held at the edge.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct CropPosition {
    pub horizontal: f64,
    pub vertical: f64,
}

impl CropPosition {
    pub const CENTER: CropPosition = CropPosition {
        horizontal: 0.5,
        vertical: 0.5,
    };

    pub fn new(horizontal: f64, vertical: f64) -> CropPosition {
        CropPosition {
            horizontal: Self::limited(horizontal),
            vertical: Self::limited(vertical),
        }
    }

    fn limited(value: f64) -> f64 {
        if value.is_nan() {
            0.5
        } else {
            value.clamp(0.0, 1.0)
        }
    }
}

/// Where the image is drawn, in frame pixels from the frame's top-left corner.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ImagePlacement {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// Why a frame can't be made.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameError {
    /// Original needs an image of at least 16x16 pixels.
    ImageTooSmall,
}

/// The exact output size and image placement for an image, shape and resolution.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct OutputFrame {
    pub size: PixelSize,
    pub image_placement: ImagePlacement,
    /// True when the image is drawn larger than its own pixel size.
    pub is_enlarged: bool,
}

impl OutputFrame {
    /// `image` is the image's size after its orientation tag.
    pub fn new(
        image: PixelSize,
        shape: FrameShape,
        resolution: Resolution,
        crop: CropPosition,
    ) -> Result<OutputFrame, FrameError> {
        let short_side: i64 = resolution.short_side();
        match shape {
            FrameShape::SixteenByNine => Ok(Self::fit_with_bars(
                image,
                PixelSize {
                    width: Self::even_ceil(short_side * 16, 9),
                    height: short_side,
                },
            )),
            FrameShape::NineBySixteen => Ok(Self::fit_with_bars(
                image,
                PixelSize {
                    width: short_side,
                    height: Self::even_ceil(short_side * 16, 9),
                },
            )),
            FrameShape::OneByOne => Ok(Self::crop(
                image,
                PixelSize {
                    width: short_side,
                    height: short_side,
                },
                crop,
            )),
            FrameShape::FourByThree => Ok(Self::crop(
                image,
                PixelSize {
                    width: short_side * 4 / 3,
                    height: short_side,
                },
                crop,
            )),
            FrameShape::Original => Self::original(image),
        }
    }

    /// The whole image, scaled to fit and centred; black bars fill the rest.
    fn fit_with_bars(image: PixelSize, frame: PixelSize) -> OutputFrame {
        let scale: f64 = (frame.width as f64 / image.width as f64)
            .min(frame.height as f64 / image.height as f64);
        let width: f64 = image.width as f64 * scale;
        let height: f64 = image.height as f64 * scale;
        OutputFrame {
            size: frame,
            image_placement: ImagePlacement {
                x: (frame.width as f64 - width) / 2.0,
                y: (frame.height as f64 - height) / 2.0,
                width,
                height,
            },
            is_enlarged: scale > 1.0,
        }
    }

    /// The image scaled to fill the frame, with the part outside the frame discarded.
    fn crop(image: PixelSize, frame: PixelSize, position: CropPosition) -> OutputFrame {
        let scale: f64 = (frame.width as f64 / image.width as f64)
            .max(frame.height as f64 / image.height as f64);
        let width: f64 = image.width as f64 * scale;
        let height: f64 = image.height as f64 * scale;
        OutputFrame {
            size: frame,
            image_placement: ImagePlacement {
                x: -(width - frame.width as f64) * position.horizontal,
                y: -(height - frame.height as f64) * position.vertical,
                width,
                height,
            },
            is_enlarged: scale > 1.0,
        }
    }

    /// The image's own size, limited to 3840x2160 (2160x3840 for portrait) and made even.
    /// All arithmetic is in whole numbers so that boundaries such as exactly 0.99 can't drift.
    fn original(image: PixelSize) -> Result<OutputFrame, FrameError> {
        if image.width < 16 || image.height < 16 {
            return Err(FrameError::ImageTooSmall);
        }
        let is_portrait: bool = image.height > image.width;
        let limit: PixelSize = if is_portrait {
            PixelSize {
                width: 2160,
                height: 3840,
            }
        } else {
            PixelSize {
                width: 3840,
                height: 2160,
            }
        };

        // s = min(1, limit.width / width, limit.height / height), kept as numerator / denominator.
        let mut scale_numerator: i64 = 1;
        let mut scale_denominator: i64 = 1;
        if limit.width * scale_denominator < image.width * scale_numerator {
            scale_numerator = limit.width;
            scale_denominator = image.width;
        }
        if limit.height * scale_denominator < image.height * scale_numerator {
            scale_numerator = limit.height;
            scale_denominator = image.height;
        }

        let mut frame: PixelSize;
        let placement: ImagePlacement;
        if scale_numerator == scale_denominator {
            frame = image;
            placement = ImagePlacement {
                x: 0.0,
                y: 0.0,
                width: image.width as f64,
                height: image.height as f64,
            };
        } else if scale_numerator * 100 >= scale_denominator * 99 {
            // Under 1% too big: trim the excess equally from both edges, the odd pixel from the far edge.
            frame = PixelSize {
                width: image.width.min(limit.width),
                height: image.height.min(limit.height),
            };
            placement = ImagePlacement {
                x: -((image.width - frame.width) / 2) as f64,
                y: -((image.height - frame.height) / 2) as f64,
                width: image.width as f64,
                height: image.height as f64,
            };
        } else {
            let scaled: PixelSize = PixelSize {
                width: image.width * scale_numerator / scale_denominator,
                height: image.height * scale_numerator / scale_denominator,
            };
            frame = scaled;
            placement = ImagePlacement {
                x: 0.0,
                y: 0.0,
                width: scaled.width as f64,
                height: scaled.height as f64,
            };
        }

        // An odd width or height loses one pixel from the right or bottom edge.
        frame.width -= frame.width % 2;
        frame.height -= frame.height % 2;
        Ok(OutputFrame {
            size: frame,
            image_placement: placement,
            is_enlarged: false,
        })
    }

    /// `numerator / denominator` rounded up to the next even whole number.
    fn even_ceil(numerator: i64, denominator: i64) -> i64 {
        let ceiling: i64 = (numerator + denominator - 1) / denominator;
        ceiling + ceiling % 2
    }
}

/// How the image sits in the frame (SPEC section 5).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Placement {
    /// The whole image is shown. 16:9 and 9:16 add black bars.
    Fit,
    /// The image fills the frame and the parts outside it are discarded.
    Crop,
}

impl Placement {
    /// 16:9 and 9:16 are Fit with bars, and 1:1 and 4:3 are Crop. Original is Fit when the whole
    /// image is kept, and Crop when the image was a little over the limit and its edges were trimmed.
    pub fn of(shape: FrameShape, frame: &OutputFrame) -> Placement {
        match shape {
            FrameShape::SixteenByNine | FrameShape::NineBySixteen => Placement::Fit,
            FrameShape::OneByOne | FrameShape::FourByThree => Placement::Crop,
            FrameShape::Original => {
                if frame.image_placement.x < 0.0 || frame.image_placement.y < 0.0 {
                    Placement::Crop
                } else {
                    Placement::Fit
                }
            }
        }
    }

    /// The word in JSON.
    pub fn json_name(self) -> &'static str {
        match self {
            Placement::Fit => "fit",
            Placement::Crop => "crop",
        }
    }

    /// The glossary's word for it, for people reading the text output.
    pub fn title(self, shape: FrameShape) -> &'static str {
        match (self, shape) {
            (Placement::Fit, FrameShape::Original) => "Whole image",
            (Placement::Crop, FrameShape::Original) => "Crop (edges trimmed)",
            (Placement::Fit, _) => "Fit with bars",
            (Placement::Crop, _) => "Crop",
        }
    }
}
