# DropletBanner

Lightweight standalone iOS SpringBoard tweak implementing the **Dynamic Island / Notch Droplet Banner** notification animation while retaining native iOS banner appearance, actions, sounds, and haptics.

## Build Options

### Option 1: Free 1-Click Cloud Build via GitHub Actions (No Mac Needed)
1. Create a new GitHub repository and upload all files from this ZIP (including `.github/workflows/build.yml`).
2. Open the **Actions** tab in your repository.
3. Click the completed **Build DropletBanner (.deb)** run and download the `DropletBanner-debs` artifact — it contains both:
   - `com.custom.dropletbanner_1.0.0_iphoneos-arm64e.deb` (RootHide)
   - `com.custom.dropletbanner_1.0.0_iphoneos-arm64.deb` (Rootless)

### Option 2: Compile Locally with Theos (macOS or Windows WSL2 Ubuntu)
```bash
# For RootHide (iphoneos-arm64e):
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

# For Rootless (iphoneos-arm64):
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```
