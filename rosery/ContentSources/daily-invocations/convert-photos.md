# Rendering the supplied source photos

The `photos/` directory contains unchanged HEIC originals. `source-manifest.json` records each SHA-256 and the corresponding printed page pair. These are editorial source files, not app resources.

The review used `heif-convert` / libheif 1.23.2. macOS `sips` returned all-black images when decoding these HEIC originals in the review environment; libheif decoded them correctly. Place `heif-convert` on `PATH` and run from this directory:

```sh
mkdir -p /tmp/rosery-photo-review
for source in photos/IMG_*.HEIC; do
  filename="${source##*/}"
  heif-convert "$source" "/tmp/rosery-photo-review/${filename%.HEIC}.jpg"
done
```

The generated JPEGs are inspection copies. Use the retained HEIC originals as the final photographic reference; do not replace them with converted images.
