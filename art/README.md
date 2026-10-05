# Artwork

Source artwork for the project. Nothing in this folder ships with the addon.

- `logo-1024.png`: the logo at full size.
- `logo-400.png`: for CurseForge and other listings.
- `logo.ps1`: draws the logo with .NET (Windows PowerShell) and writes the PNGs plus `logo.tga` (128x128, 32-bit, uncompressed) for the game.

Regenerate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File art\logo.ps1 -OutDir art\out
```

Then copy `art\out\logo.tga` to `images\logo.tga` and the PNGs you need into `art\`.
