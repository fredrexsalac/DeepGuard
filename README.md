# DeepGuard

**AI-Powered Deepfake Detection — Hybrid CNN–RNN Model**

DeepGuard is a Flutter mobile application that detects AI-manipulated faces
in photos and videos using a hybrid CNN–RNN neural network running on-device
via TensorFlow Lite.

## Features

- **Image Detection** — Upload any photo for deepfake classification
- **Video Detection** — Frame-by-frame analysis with confidence score
- **Real-Time Camera** — Live face scanning at ~6 inference fps
- **On-Device Inference** — TFLite model, no data leaves the device

## Architecture

```
Input → Preprocess (128×128) → CNN (spatial) → RNN (temporal)
      → Parallel Fusion → Neuro-Symbolic Reasoning → REAL / FAKE
```

## Development Status

Model training in progress. Simulation mode active until `.tflite` model
is bundled under `assets/models/deepguard_model.tflite`.

To activate real inference, set `kSimulationMode = false` in
`lib/screens/realtime_camera_screen.dart`.
