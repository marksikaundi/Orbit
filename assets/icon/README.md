# Orbit app icon

| File | Use |
| --- | --- |
| `orbit-1024.png` | Source artwork |
| `AppIcon.icns` | macOS Dock / Finder (`Orbit.app`) |
| `Info.plist` | Bundle metadata for `Orbit.app` |
| `orbit-256.png` / `orbit-128.png` | Preview / tooling |

`zig build run` on macOS packages `zig-out/Orbit.app` and also sets the Dock icon at runtime from the embedded PNG in `src/platform/orbit-icon-256.png`.

To regenerate `AppIcon.icns` after changing the artwork:

```bash
# create RGBA iconset sizes, then:
iconutil -c icns orbit.iconset -o AppIcon.icns
```
