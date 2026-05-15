# AppIcon placeholder

This `.appiconset` ships without bitmap PNGs so xcodegen + xcodebuild can
generate the project without binary art assets in source control. Drop the
ten required PNGs into this directory before building a release:

| File | Size |
|------|------|
| `AppIcon-16.png` | 16×16 |
| `AppIcon-16@2x.png` | 32×32 |
| `AppIcon-32.png` | 32×32 |
| `AppIcon-32@2x.png` | 64×64 |
| `AppIcon-128.png` | 128×128 |
| `AppIcon-128@2x.png` | 256×256 |
| `AppIcon-256.png` | 256×256 |
| `AppIcon-256@2x.png` | 512×512 |
| `AppIcon-512.png` | 512×512 |
| `AppIcon-512@2x.png` | 1024×1024 |

The asset catalog also belongs in `Resources/Assets.xcassets/AccentColor.colorset/`
once color tokens are exported from Figma.
