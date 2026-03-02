# calx (Codemagic + LiveContainer friendly)

This repo is designed to build an **unsigned IPA** (Payload-based) for **LiveContainer**.

## What you get
- OLED pitch-black app UI (Flutter)
- Gesture controls:
  - Single tap: start/stop recording (stays black)
  - While recording: tiny red dot + optional tiny REC text (top-left)
  - Long press (hold): camera preview + zoom/FPS controls
  - Double tap: back to OLED black
  - Triple tap: utility overlay
- iOS native camera engine (AVFoundation) saves recordings to **Documents/** (Files), NOT Photos.

## Build (Codemagic)
Just connect this repo in Codemagic and run workflow:
- `ios-livecontainer-unsigned`

It will:
1. `flutter create` iOS scaffold (Swift)
2. Inject native overrides from `ios_overrides/`
3. `pod install`
4. `xcodebuild archive` with signing disabled
5. Package an unsigned `.ipa` in `build/ios/ipa/calx.ipa`

## LiveContainer
Install the produced IPA into LiveContainer. Recordings save into the app's Documents directory.

> Note: This repo intentionally does NOT commit the `ios/` folder.
> Codemagic generates it every build, then injects your native iOS files.


## Podfile
A Podfile template is included at `ios_overrides/Podfile` and will be copied into `ios/Podfile` if Flutter doesn't create one on CI.
