# polysix
Korg Polysix patch dumper for WAV files captured from cassette.
Can dump to a raw hex file, or to a human-readable text file.

```
Usage:
  polysix <infile> <outfile> [--hex | --text] [-v]
  polysix (-h | --help)
  polysix --version

Options:
  -h --help     Show this screen.
  --version     Show version information.
  -v            Verbose mode.
  --hex         Dump patches as raw hexadecimal data. (default mode)
  --text        Dump patches as human readable text.

Examples:
  polysix patches.wav patches.hex
  polysix patches.wav patches.txt --text

Notes:
  Supported input file formats: 8- and 16-bit WAV files of any sample rate.
  (Use sox, ffmpeg, or Audacity to convert to WAV if necessary.)
```
