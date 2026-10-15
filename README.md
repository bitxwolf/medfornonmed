# HoloMed 3D (iPhone Edition) — Pure Metal Shading Language (MSL / C++14)

> **The Mad-Scientist Architecture:** Raw compute and fragment shaders directly targeting **Apple Silicon's Unified Memory Architecture (UMA)**, rendering **100,000 instanced erythrocytes (red blood cells)** along a 3D Catmull-Rom cardiovascular spline, dynamic arterial blockages (atherosclerosis / acute thrombosis), and procedural myocardial tissue ischemia shaders running at a locked **120 FPS ProMotion** with **zero CPU overhead** and **zero memory copies** between CPU and GPU.

Built for **Windows development using `xtool`** (the open-source Xcode replacement for building and sideloading iOS apps directly from SwiftPM).

---

## 1. Architectural Highlights

### ⚡ Zero-Copy Apple Silicon Unified Memory Architecture (UMA)
* **Physical Shared Memory:** On Apple Silicon (A16/A17/A18 Pro and M-series chips), CPU and GPU share high-bandwidth physical LPDDR memory.
* **`MTLResourceStorageModeShared`:** All 100,000 blood cell instance structs (`BloodCellInstance`, 80 bytes each) and camera uniforms are allocated in shared memory (`~7.63 MB` total).
* **Zero CPU-to-GPU Copies:** The CPU directly updates camera matrices via raw pointers. The GPU compute kernel (`simulate_blood_cells_kernel`) reads and updates the 100,000 particle states in place. The vertex shader (`blood_cell_vertex`) immediately consumes the updated buffer as an instance buffer in the exact same frame.

### 🚀 Locked 120 FPS ProMotion Pipeline
* `CADisableMinimumFrameDurationOnPhone: true` enabled in `Info.plist` to bypass iOS 60Hz display throttling.
* `MTKView.preferredFramesPerSecond = 120`.
* **Triple-Buffering with Semaphore (`DispatchSemaphore(value: 3)`):** Allows the CPU to queue up to 3 frames of work ahead of the GPU without pipeline stalls or stutter.

### 🩸 Massively Parallel Catmull-Rom Spline Simulation
* 100,000 erythrocytes animated along the complete cardiovascular circuit:
  $$\text{SVC/IVC} \rightarrow \text{Right Atrium} \rightarrow \text{Tricuspid Valve} \rightarrow \text{Right Ventricle} \rightarrow \text{Pulmonary Trunk} \rightarrow \text{Alveolar Bed (Lungs)} \rightarrow \text{Left Atrium} \rightarrow \text{Mitral Valve} \rightarrow \text{Left Ventricle} \rightarrow \text{Aorta} \rightarrow \text{LAD Artery}$$
* **Evans-Fung Biconcave Geometry:** Custom parametric erythrocyte geometry with center indentation and thickness falloff.
* **Hemodynamic Physics:** Poiseuille parabolic velocity profile (fastest in centerline, viscous boundary layer at lumen wall) with Reynolds turbulence and upstream cell clustering upon arterial stenosis.
* **Alveolar Oxygenation Shift:** Venous deoxygenated blue (`0.15, 0.38, 0.88`) transitions smoothly in the alveolar capillary bed to arterial crimson red (`0.96, 0.06, 0.08`).

### 🫀 Acute Myocardial Infarction (AMI) Pathology Engine
* **Procedural Plaque & Thrombus:** Renders dynamic atherosclerotic constriction rings and platelet-fibrin clots on target vessels (e.g., Left Anterior Descending Artery `FMA_7101`).
* **Tissue Ischemia Shader (`TissueStateShader`):** Procedural myocardial hypoxia transitioning from healthy perfused tissue into dark cyanotic violaceous tissue with a rhythmic low-frequency hypoxic pulse ($\sin(\omega t)$), progressing to mottled infarcted necrosis.

### 🧠 Universal OpenAI-Compatible AI Tutor & Dual-Output Streaming
* Works with **any OpenAI-compatible endpoint** (OpenRouter, Groq, Together AI, OpenAI, or local Ollama/LM Studio over WiFi).
* **Auto-Fetch Models:** Automatically queries `GET {base_url}/models` to populate model choices.
* **Multiplexed Streaming Parser (`DualOutputParser`):** Simultaneously streams explanatory markdown prose and extracts embedded `<scene_cmd>` XML blocks in real time, synchronizing camera framing and pathology triggers with the narration.
* **3 Adaptive Comprehension Levels:**
  1. `layperson`: "Everyday Biology" with plain-English analogies (fuel lines, one-way swing doors).
  2. `pre_med`: Anatomical terminology and physiological mechanisms (pressure gradients, depolarization).
  3. `clinician`: Advanced hemodynamics, cellular necrosis, and direct StatPearls/PubMed citations.

---

## 2. Directory Structure

```text
iphone&xtool/
├── xtool.yml                          # xtool build, bundle, and deployment configuration
├── Package.swift                      # SwiftPM package manifest defining HoloMedMetal & HoloMedApp
├── Info.plist                         # 120 FPS ProMotion, Metal, and Local Network permissions
├── Entitlements.plist                 # Sideloading and development entitlements
├── Sources/
│   ├── HoloMedMetal/                  # Metal Compute & Render Engine
│   │   ├── include/
│   │   │   ├── ShaderTypes.h          # 16-byte aligned C++/MSL/Swift shared UMA data structures
│   │   │   └── module.modulemap       # Clang module map for seamless Swift import
│   │   ├── Shaders/
│   │   │   └── Shaders.metal          # MSL Compute kernel (100k cells), instanced RBC vertex/frag,
│   │   │                              # tissue ischemia/necrosis shaders, and arterial blockage beacon
│   │   ├── Renderer/
│   │   │   ├── MetalRenderer.swift    # 120 FPS MTKView delegate, UMA shared buffer allocation, triple buffering
│   │   │   ├── AnatomyMeshBuilder.swift # Procedural 3D anatomical organs (Heart, Chambers, LAD, Lungs, Ribs)
│   │   │   ├── CameraRig.swift        # Bounding-sphere framing math, quaternion SLERP, orbit/zoom/pan
│   │   │   └── SceneController.swift  # Deterministic <scene_cmd> executor for 3D walkthroughs
│   │   └── Math/
│   │       ├── MatrixMath.swift       # SIMD matrix transforms, perspective projection, lookAt, normal matrices
│   │       └── SplineMath.swift       # Catmull-Rom cardiovascular waypoint generator
│   └── HoloMedApp/                    # Native iOS Host Application
│       ├── HoloMedApp.swift           # @main SwiftUI app entry point
│       ├── State/
│       │   └── AppState.swift         # Observable state: Mode, Comprehension Level, Models, Chat
│       ├── Services/
│       │   ├── OpenAICompatClient.swift # Universal Async HTTP SSE streaming client & model auto-fetch
│       │   ├── DualOutputParser.swift # Real-time streaming parser multiplexing <scene_cmd> and text
│       │   └── MedicalKnowledgeGraph.swift # Local StatPearls/PubMed grounding & anatomical edge graph
│       ├── UI/
│       │   ├── MainContentView.swift  # Main viewport combining 120 FPS Metal canvas and HUD overlays
│       │   ├── HoloMedMetalView.swift # UIViewRepresentable bridge for MTKView with touch gesture handlers
│       │   ├── TopNavBar.swift        # Mode switcher, Comprehension level menu, Settings button
│       │   ├── StructureInspectorHUD.swift # Tap-to-inspect card with FMA IDs and action buttons
│       │   ├── AITutorDrawer.swift    # Floating AI tutor drawer with live streaming, step badges, and citations
│       │   ├── ProviderSettingsView.swift # Universal OpenAI base URL, API key, and auto-fetch model picker
│       │   └── TimelineScrubberView.swift # Step scrubber for replaying multi-step walkthroughs
│       └── Resources/
│           └── manifest.json          # FMA 3D anatomical registry manifest
```

---

## 3. How to Build & Run on Windows with `xtool`

`xtool` is an open-source toolchain that compiles SwiftPM iOS packages into signed `.ipa` / `.app` bundles on non-macOS platforms (Windows via WSL / Linux / macOS).

### Step 1: Install WSL (Windows Subsystem for Linux)
On your Windows PowerShell (Administrator):
```powershell
wsl --install
```
*(Reboot your PC if prompted to complete WSL installation).*

### Step 2: Install `xtool` inside WSL
Open your WSL terminal (e.g. Ubuntu):
```bash
# 1. Install required system build tools
sudo apt-get update && sudo apt-get install -y curl git clang libxml2 libicu-dev usbmuxd

# 2. Install xtool CLI
curl -fsSL https://xtool.sh/install.sh | bash

# 3. Verify xtool installation
xtool --version
```

### Step 3: Connect your iPhone to Windows
1. Connect your physical iPhone to your Windows PC via USB cable.
2. Tap **"Trust This Computer"** on your iPhone screen and enter your passcode.
3. In WSL, ensure `usbmuxd` is running to detect iOS USB devices:
   ```bash
   sudo service usbmuxd start
   xtool devices
   ```

### Step 4: Build, Sign, and Sideload to iPhone
Navigate to the project folder from WSL:
```bash
cd /mnt/c/antigravity/medfornonmed/iphone\&xtool

# Run the automated build, sign, and install pipeline
xtool dev
```
* **First-Time Sign-In:** `xtool` will prompt for your Apple ID credentials (free developer accounts are fully supported) to generate a free development certificate and provisioning profile.
* **Launch:** Once installed, open **Settings $\rightarrow$ General $\rightarrow$ VPN & Device Management** on your iPhone to trust your developer certificate, then launch **HoloMed 3D**!

---

## 4. Canonical FMA Anatomical Registry

| FMA ID | Common Name | Latin Name | Organ System | Clinical Role |
| :--- | :--- | :--- | :--- | :--- |
| `FMA_7088` | Heart | *Cor* | Cardiovascular | Primary muscular pump |
| `FMA_7096` | Right Atrium | *Atrium dextrum cordis* | Cardiovascular | Receives venous blood from SVC/IVC |
| `FMA_7098` | Right Ventricle | *Ventriculus dexter cordis* | Cardiovascular | Ejects blood into pulmonary trunk |
| `FMA_7099` | Left Atrium | *Atrium sinistrum cordis* | Cardiovascular | Receives oxygenated pulmonary return |
| `FMA_7097` | Left Ventricle | *Ventriculus sinister cordis* | Cardiovascular | Systemic pump; primary site of MI necrosis |
| `FMA_7101` | LAD Coronary Artery | *Ramus interventricularis anterior* | Cardiovascular | "The Widowmaker"; site of acute thrombosis |
| `FMA_7100` | Right Coronary Artery | *Arteria coronaria dextra* | Cardiovascular | Supplies RV, SA node, inferior wall |
| `FMA_3734` | Aorta (Ascending/Arch) | *Aorta ascendens et arcus aortae* | Cardiovascular | Primary systemic trunk |
| `FMA_7309` | Right Lung | *Pulmo dexter* | Respiratory | Trilobed gas-exchange organ |
| `FMA_7310` | Left Lung | *Pulmo sinister* | Respiratory | Bilobed gas-exchange organ |
| `FMA_7480` | Thoracic Ribcage & Sternum | *Cavea thoracis et sternum* | Skeletal | Superficial protective cage (X-ray occluder) |

---

## 5. Mathematical Formulas Implemented

### 1. Catmull-Rom Spline Position & Tangent
$$\mathbf{P}(u) = \frac{1}{2} \begin{bmatrix} 1 & u & u^2 & u^3 \end{bmatrix} \begin{bmatrix} 0 & 2 & 0 & 0 \\ -1 & 0 & 1 & 0 \\ 2 & -5 & 4 & -1 \\ -1 & 3 & -3 & 1 \end{bmatrix} \begin{bmatrix} \mathbf{P}_{i-1} \\ \mathbf{P}_i \\ \mathbf{P}_{i+1} \\ \mathbf{P}_{i+2} \end{bmatrix}$$

$$\mathbf{T}(u) = \frac{d\mathbf{P}(u)}{du}$$

### 2. Evans-Fung Biconcave Erythrocyte Shape
Thickness $D(r)$ as a function of radial distance $r \in [0, R]$:
$$t(r) = D_0 \cdot \sqrt{1 - \left(\frac{r}{R}\right)^2} \cdot \left[ a_0 + a_1\left(\frac{r}{R}\right)^2 + a_2\left(\frac{r}{R}\right)^4 \right]$$

### 3. Bounding-Sphere Camera Framing
For $k$ target centroids $\mathbf{c}_i$ with radii $r_i$:
$$\mathbf{C} = \frac{1}{k} \sum_{i=1}^{k} \mathbf{c}_i, \quad R = \max_{i} \left( \|\mathbf{c}_i - \mathbf{C}\|_2 + r_i \right)$$
$$d = \frac{1.35 \cdot R}{\sin\left(\frac{\theta_{\text{fov}}}{2}\right)}$$
Orientations are interpolated smoothly using spherical linear interpolation ($\text{SLERP}$) over $\Delta t = 0.9\text{ s}$.
