# Ready Hard-Disc Templates

Bundled ready-image templates live in this directory.

Names must follow:

- `ide_101x16x63.hdf.zlib`
- `st506_615x8x32.hdf`

Regenerate the remaining template workflow with:

```bash
./scripts/author_ready_hdf_templates.sh \
  --app /path/to/Arculator.app \
  --ide-config "Template IDE" \
  --st506-config "Template ST506"
```

To use the IDE-first guest automation helper:

```bash
./scripts/author_ready_hdf_templates.sh \
  --app /path/to/Arculator.app \
  --ide-config "Template IDE" \
  --st506-config "Template ST506" \
  --ide-guest-automation /Users/alex/work/arculator-mac/scripts/automate_ide_template_guest.sh
```

The IDE template is seeded from the externally supplied formatted `HD4.HDF`
artifact, then stored in the bundle as zlib-compressed
`ide_101x16x63.hdf.zlib`. The decompressed HDF is preserved byte-for-byte from
the seed. Its FileCore disc record is at `0xFC0`, matching the
legacy/RPCEmu-style header layout that Arculator's IDE emulation still
supports.

The authoring script remains available for regenerating templates. For ST-506 it
still creates blank candidate images, attaches them through the AppleScript API,
pauses for guest-side formatting, then verifies the host-side classifier reports
`initialized` before moving the finished HDF into this directory.

Recommended authoring configs:

- `Template IDE`
  - Base machine: `A3010`
  - Reason: New I/O machine with IDE support and RISC OS 3.1 defaults.
- `Template ST506`
  - Base machine: `Archimedes 440/1`
  - Reason: Old I/O + ST-506 preset with RISC OS defaults.

Suggested checklist:

1. Build and launch `Arculator.app`.
2. Create the two configs above in the UI and save them once without any hard discs attached.
3. Run the authoring script; it will keep the existing IDE seed unless `--force` is used.
4. For ST-506, partition/format the attached hard disc inside RISC OS until it is usable.
5. Let the script reboot for validation and confirm the disc mounts on first desktop load.
6. Rebuild the app so the new template files are bundled in `Resources/templates/`.
7. Verify `ready` creation and startup initialization both clone the bundled template.

IDE seed notes:

- The canonical IDE geometry is `101x16x63`, not the older planned `100x16x63`.
- Do not strip or truncate the leading legacy header layout before compressing `ide_101x16x63.hdf.zlib`; Arculator detects this layout and sets `skip512` for IDE reads/writes after decompression.
- [`scripts/automate_ide_template_guest.sh`](/Users/alex/work/arculator-mac/scripts/automate_ide_template_guest.sh) is retained as a fallback/debugging helper, not the primary IDE template path.
