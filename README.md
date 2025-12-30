# Sangeet 3.0
> **The Ultimate Audiophile Music Player for macOS**

![Project Walkthrough](path/to/walkthrough.gif)

Sangeet is a premium, native macOS music player built for audiophiles who demand bit-perfect audio quality without compromising on aesthetics. Powered by the industry-standard **BASS Audio Engine** and wrapped in a stunning **Glassmorphic SwiftUI** interface, Sangeet bridges the gap between professional audio tools and modern design.

---

## ✨ Key Features

### 🎧 Audiophile-Grade Audio Engine
- **Bit-Perfect Output**: Bypasses the macOS system mixer to deliver unaltered audio directly to your DAC.
- **Exclusive Access (Hog Mode)**: Takes complete control of your audio device to prevent interference from other apps.
- **Native Sample Rate Switching**: Automatically adjusts your DAC's sample rate to match the source file (up to 192kHz/32-bit).
- **True Gapless Playback**: Zero-latency transitions between tracks using advanced preloading.
- **Smart Crossfade**: "Kill Switch" technology ensures smooth transitions without overlapping clashes, even during rapid skipping.
- **Volume Normalization**: Integrated ReplayGain support for consistent volume levels across your library.

### 🎨 Stunning Visuals
- **Glassmorphism UI**: Beautiful, translucent interface elements that blend with your desktop.
- **Floating Dock**: A compact, interactive mini-player that floats above your windows.
- **Visual Equalizer**: 8-band parametric EQ with a glowing, interactive curve and preset management.
- **Squiggly Progress Bar**: Unique, animated playback progress inspired by Android 13.
- **Radial Settings Menu**: A futuristic, gesture-driven settings interface.

### 📂 Powerful Library Management
- **Folder-Based Library**: Drag and drop your music folders directly—no "importing" or duplicating files.
- **Instant Search**: Global Cmd+K search to find any track, album, or artist instantly.
- **Smart Metadata**: Automatically fetches high-res artwork and corrects tags.
- **Infinite Queue**: Never stops playing music, automatically queuing similar tracks when your playlist ends.
- **Stats & History**: Track your listening habits with detailed statistics.

---

## 📸 Screenshots

| Home & Library | Visual Equalizer |
|:---:|:---:|
| ![Home View](path/to/screenshot_home.png) | ![EQ View](path/to/screenshot_eq.png) |

| Floating Dock | Radial Settings |
|:---:|:---:|
| ![Floating Dock](path/to/screenshot_dock.png) | ![Settings](path/to/screenshot_settings.png) |

---

## 🛠️ Technology Stack
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI (macOS 14+)
- **Audio Engine**: [Un4seen BASS](https://www.un4seen.com/) (C++ Library bridged to Swift)
- **Database**: [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite wrapper)
- **Hardware Integration**: CoreAudio (for HAL/DAC control)

---

## 🏗️ Installation & Build

1. **Clone the repository**
   ```bash
   git clone https://github.com/YashvardhanATRgithub/Sangeet.git
   cd Sangeet
   ```

2. **Open in Xcode**
   ```bash
   open Sangeet3.xcodeproj
   ```

3. **Build & Run**
   - Ensure you have the `libbass.dylib` in `Data/Audio/BASS/` (included in repo).
   - Press `Cmd+R` to build and run.

---

## 🙌 Acknowledgements

Special thanks to the creators of the libraries that make Sangeet possible:

- **[Un4seen Developments](https://www.un4seen.com/)**: For the incredible **BASS Audio Library**, which powers the core audio engine, DSP, and gapless playback features.
- **[Gwendal Roué](https://github.com/groue)**: For **GRDB.swift**, the robust SQLite toolkit that handles the music library database.
- **Apple**: For SwiftUI and CoreAudio.

---

**Made with ❤️ by Yashvardhan**
