<div align="center">

<img src="dropletbannerprefs/Resources/header_icon@3x.png" width="110" height="110" alt="DropletBanner Icon" />

# DropletBanner

**Fluid Dynamic Island & notch droplet animations for native iOS notification banners.**

![Version](https://img.shields.io/badge/Version-1.6.0-0A84FF?style=for-the-badge)
![iOS](https://img.shields.io/badge/iOS-15.0%2B-1C1C1E?style=for-the-badge&logo=apple&logoColor=white)
![Architecture](https://img.shields.io/badge/RootHide%20%7C%20Rootless-arm64e%20%2F%20arm64-30D158?style=for-the-badge)
![Package](https://img.shields.io/badge/Package-com.billie.dropletbanner-5856D6?style=for-the-badge)

</div>

---

## Overview

**DropletBanner** is a lightweight, standalone iOS SpringBoard tweak that animates incoming notification banners out of the Dynamic Island or notch as a smooth liquid droplet and retracts them seamlessly back inside on dismissal.

It hooks `SBNotificationBannerDestination` cleanly without replacing or restyling Apple's banner views, preserving your native iOS appearance (including Liquid Glass), preview privacy, sounds, haptics, quick actions, and Long Look gestures.

---

## Features

- **Liquid Droplet Emergence** — A 120Hz `CADisplayLink`-driven spring animation stretches a fluid teardrop with a curved Bezier neck directly out of the Dynamic Island or notch before blooming into your native banner.
- **Reversed Retraction on Dismiss** — Retracts notifications smoothly back into the Dynamic Island on both **auto-dismiss** and **swipe-up dismissal** (picking up right where your finger releases the banner).
- **Rapid-Notification Ready** — Per-banner container isolation and instant handoff keep back-to-back notifications fluid with no overlapping visuals or stuck states.
- **100% Native Banner Retention** — Keeps stock iOS materials, notification actions, haptics, sounds, and Lock Screen privacy intact.
- **Smart Fallbacks** — Automatically falls back to the stock iOS animation in landscape orientation and when **Reduce Motion** is enabled.
- **Zero Heavy Dependencies** — Pure `UIKit`, `QuartzCore`, and `Preferences.framework` (no Cephei required), with instant live-reload in Settings—no respring needed after changing sliders or toggles.

---

## Preferences

Configure everything live under **Settings → DropletBanner**:

| Setting | Description | Default |
| :--- | :--- | :---: |
| **Enable Droplet Banner** | Master toggle to enable or disable the animation instantly. | `On` |
| **Retract on Dismiss** | Plays the reversed droplet retraction on auto-dismiss and swipe-up. | `On` |
| **Animation Duration** | Controls overall entry and retraction speed (`0.25s` – `0.85s`). | `0.48s` |
| **Droplet Elasticity** | Adjusts vertical stretch and liquid bulge intensity (`0.40` – `1.50`). | `1.00` |

---

## Compatibility

- **iOS Versions:** iOS 15.0 and later
- **Jailbreaks:**
  - **RootHide** (`iphoneos-arm64e`)
  - **Rootless** (`iphoneos-arm64`)
- **Devices:** Dynamic Island iPhones, Notched Face ID iPhones, and non-notched fallback

---

## Installation

1. Download the latest `.deb` package from the **Releases** page (or the **Actions → `DropletBanner-debs`** build artifact):
   - **RootHide:** `com.billie.dropletbanner_1.6.0_iphoneos-arm64e.deb`
   - **Rootless:** `com.billie.dropletbanner_1.6.0_iphoneos-arm64.deb`
2. Share or open the `.deb` in **Sileo** or **Zebra** and tap **Install**.
3. Tap **Restart SpringBoard** to activate the tweak.

---

## Building from Source

### Cloud Build (GitHub Actions)
Push any change or trigger **Build DropletBanner (.deb)** manually from the **Actions** tab (`.github/workflows/main.yml`). Both RootHide (`arm64e`) and Rootless (`arm64`) `.deb` packages are uploaded automatically under the **`DropletBanner-debs`** artifact.

### Local Build (Theos)
Requires [RootHide Theos](https://github.com/roothide/theos) and a patched iOS 16.5 SDK:

```bash
# Build for RootHide (iphoneos-arm64e)
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

# Build for Rootless (iphoneos-arm64)
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

Credits
Developer: Billie (@Billie0x)
