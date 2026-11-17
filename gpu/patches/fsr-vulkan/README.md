# Local changes to gpu/third_party/fsr-vulkan

The submodule points at upstream FireBurn/FSR-Vulkan (`c64f093`). `build.sh` applies the
patches here to its working tree when they are not applied yet:

- `0001-...`: `GOW3_FSR4_PROFILE` (GPU time per FSR 4 pass) and `GOW3_FSR4_STATS` (driver
  statistics of each pass) in the FSR 4 v07 provider.
- `0002-...`: `#include <mutex>` in the FFX Vulkan backend; libc++ (the Windows MSYS2 CLANG64
  build) does not include it transitively.
- `0003-...` (from SpartanPort, FelipePrado0/SpartanPort `gpu/patches/fsr-vulkan/0004`): frame
  generation (3.1.6 FI/OF) frees what each frame stages. The context never tagged the bridge's frame
  (`BridgeBeginFrame`) nor retired it (`BridgeRetireFrame`), so every constant buffer and descriptor
  pool it made lived on and the lookups grew each frame. Retired ones are now reused.
