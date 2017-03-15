#!/usr/bin/python
#
# polysix.py - converts WAV file Korg Polysix cassette patch dumps
# Written by Joan Touzet <joant@atypical.net> March 2017
#
"""Korg Polysix patch dumper for WAV files captured from cassette.
Can dump to a raw hex file, or to a human-readable text file.

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
"""

import audioop
import docopt
import math
import statistics
import struct
import sys
import wave

PNAMES = ["A-1", "A-2", "A-3", "A-4", "A-5", "A-6", "A-7", "A-8",
          "B-1", "B-2", "B-3", "B-4", "B-5", "B-6", "B-7", "B-8",
          "C-1", "C-2", "C-3", "C-4", "C-5", "C-6", "C-7", "C-8",
          "D-1", "D-2", "D-3", "D-4", "D-5", "D-6", "D-7", "D-8"]

def fileopen(fname):
    fp = wave.open(fname, 'rb')
    params = fp.getparams()
    return (fp, params)

def getdata(fp, params):
    rawdata = fp.readframes(params.nframes)
    if params.sampwidth == 1:
        data = list( struct.unpack('B' * len(rawdata), rawdata) )
        data = [x-0x80 for x in data]
    elif params.sampwidth == 2:
        data = list( struct.unpack('h' * (len(rawdata)//2), rawdata) )
    return (data)

def readbit(data, offset, params):
    # Read a 0 or a 1 starting from data starting at data[offset].
    # Returns 0 or 1 and the length of data read.
    # 0 is of length 320us, 1 is of length 640us
    ONELEN = math.floor(0.000320 * params.framerate)
    ZEROLEN = math.floor(0.000640 * params.framerate)
    HALFLEN = math.floor(0.000480 * params.framerate)

    ctr = 0
    extra = 0
    last = data[offset]

    for idx in range(offset, len(data)):
        cur = data[idx]
        if cur == 0:
            extra += 1
            continue
        # If x ^ y < 0 then x and y have different signs
        if cur ^ last >= 0:
            ctr += 1
            last = cur
        else:
            # Zero crossing
            last = cur
            if (ctr >= (ONELEN - params.sampwidth) and ctr < HALFLEN):
                return (1, ctr+extra)
            #elif (ctr > HALFLEN and ctr <= (ZEROLEN + params.sampwidth)):
            elif (ctr > HALFLEN):
                return (0, ctr+extra)
            else:
                raise Exception("Corrupt data, found peak of length {} @ idx {}".format(ctr, offset))
                break

def findstart(data, params):
    # Finds the first meaningful zero crossing in data.
    # Skip to the first sample that is > 1 sdev away from the mean.
    sd = statistics.stdev(data)
    for ctr in range(len(data)):
        if abs(data[ctr]) > sd:
            break
    # Now skip ahead to the next zero crossing, since the first
    # bit may be truncated if ctr = 0
    last = 0
    for idx in range (ctr, len(data)):
        cur = data[idx]
        if cur ^ last >= 0:
            last = cur
        else:
            break
    # Now read bits until we get a 0 back
    while True:
        (bit, length) = readbit(data, idx, params)
        if bit == 0:
            return idx
        else:
            idx += length


def readbyte(data, offset, params):
    # Reads a byte from data starting at data[offset].
    # Each data byte has one 0 start bit and two 1 stop bits.
    # Bytes are little-endian.
    # Returns the byte read and the length of data consumed.
    (start, length) = readbit(data, offset, params)
    if start != 0:
        raise Exception("Data does not start with a zero!")

    # Wish this was less procedural, but it'll do
    byte = 0
    idx = offset + length
    (b0, length) = readbit(data, idx, params)
    byte += b0
    idx += length

    (b1, length) = readbit(data, idx, params)
    byte += b1 << 1
    idx += length

    (b2, length) = readbit(data, idx, params)
    byte += b2 << 2
    idx += length

    (b3, length) = readbit(data, idx, params)
    byte += b3 << 3
    idx += length

    (b4, length) = readbit(data, idx, params)
    byte += b4 << 4
    idx += length

    (b5, length) = readbit(data, idx, params)
    byte += b5 << 5
    idx += length

    (b6, length) = readbit(data, idx, params)
    byte += b6 << 6
    idx += length

    (b7, length) = readbit(data, idx, params)
    byte += b7 << 7
    idx += length

    (stop, length) = readbit(data, idx, params)
    if stop != 1:
        raise Exception ("Data does not have first stop bit!")
    idx += length
    (stop, length) = readbit(data, idx, params)
    if stop != 1:
        raise Exception ("Data does not have second stop bit!")
    idx += length
    
    #print (b7, b6, b5, b4, b3, b2, b1, b0, f"{byte:#04x}")

    return (byte, (idx-offset))

def readpatch(data, offset, params):
    # Reads a Korg Polysix patch from data starting at data[offset].
    # Returns the patch as a list of 16 bytes, plus the total number
    # of bytes read. Layout follows.
    #
    # Control voltages:
    # 00  Effect Speed/Intensity
    # 01  VCF Cutoff
    # 02  EG Intensity
    # 03  Resonance
    # 04  Attack
    # 05  Decay
    # 06  Sustain
    # 07  Release
    # 08  Kbd. Tracking
    # 09  PW/PWM
    # 0A  PWM Speed
    # 0B  MG Frequency
    # 0C  MG Delay
    # 0D  MG Level
    # 
    # Switches:
    # 0E - bit0,1 VCO Octave
    #      bit2,3 VCO Waveform
    #      bit4,5 Suboscillator 
    #      bit6,7 Modulation
    # 
    # 0F - bit0    VCA EG/Gate switch
    #      bit1..3 Effect Select
    #      bit4..7 Attenuator
    idx = offset
    patch = []
    for ctr in range(16):
        (byte, length) = readbyte(data, idx, params)
        patch.append(byte)
        idx += length
    return (patch, idx-offset)

def readnpatches(data, offset, n, params):
    # Reads n Korg Polysix patches from data starting at data[offset].
    # Returns a list of n patches and the total bytes read.
    patches = []
    idx = offset
    for ctr in range(n):
        (patch, length) = readpatch(data, idx, params)
        patches.append(patch)
        idx += length
    return (patches, idx-offset)

def checksum(patches):
    # Calculates checksum of all patch data, which is bottom byte of sum
    # of all patch bytes
    cksum = 0
    for patch in patches:
        for byte in patch:
            cksum += byte
    return (cksum & 0xff)

def printpatch(patch, fp):
    octaves = ["16'", "8'", "4'", "undefined"]
    fp.write ("VCO Octave: {}\n".format(octaves[ patch[14] & 0b11 ]))
    waveforms = ["PW", "|\ (Sawtooth)", "PWM", "undefined (Sawtooth?)"]
    fp.write ("VCO Waveform: {}\n".format(waveforms[ (patch[14] & 0b1100) >> 2 ]))
    fp.write ("PW/PWM: {:.1f}\n".format(patch[9]/25.5))
    fp.write ("PWM Speed: {:.1f}\n".format(patch[10]/25.5))
    subosc = ["Off", "2 Oct Down", "1 Oct Down", "undefined"]
    fp.write ("Sub Osc: {}\n".format(subosc[ (patch[14] & 0b110000) >> 4 ]))
    fp.write ("\n")

    fp.write ("VCF Cutoff: {:.1f}\n".format(patch[1]/25.5))
    fp.write ("Resonance: {:.1f}\n".format((255-patch[3])/25.5))
    fp.write ("EG Intensity: {:.1f}\n".format(patch[2]/25.5-5))
    fp.write ("Kbd. Track: {:.1f}\n".format(patch[8]/25.5))
    fp.write ("\n")

    vca = ["_|-|_ (Gate)", "EG"]
    fp.write ("VCA Mode: {}\n".format(vca[ (patch[15] & 0b1) ]))
    atten = [ "-10", "-8", "-6", "-4",
              "-2", "0", "+2", "+4",
              "+6", "+8", "+10", "undefined (1011)",
              "undefined (1100)", "undefined (1101)",
              "undefined (1110)", "undefined (1111)"]
    fp.write ("VCA Attenuator: {}\n".format(
        atten[ (patch[15] & 0b11110000) >> 4 ]))
    fp.write ("\n")
        
    fp.write ("MG Frequency: {:.1f}\n".format(patch[11]/25.5))
    fp.write ("MG Delay: {:.1f}\n".format(patch[12]/25.5))
    fp.write ("MG Level: {:.1f}\n".format(patch[13]/25.5))
    subosc = ["VCA", "VCF", "VCO", "undefined (VCF?)"]
    fp.write ("MG Mod: {}\n".format(subosc[ (patch[14] & 0b11000000) >> 6 ]))
    fp.write ("\n")

    fp.write ("Attack: {:.1f}\n".format(patch[4]/25.5))
    fp.write ("Decay: {:.1f}\n".format(patch[5]/25.5))
    fp.write ("Sustain: {:.1f}\n".format(patch[6]/25.5))
    fp.write ("Release: {:.1f}\n".format(patch[7]/25.5))
    fp.write ("\n")

    fxmode = ["Off", "Chorus", "Phase", "undefined (011)",
              "Ensemble", "undefined (101)", "undefined (110)",
              "undefined (111)"]
    fp.write ("Effects Mode: {}\n".format(fxmode[ (patch[15] & 0b1110) >> 1 ]))
    fp.write ("Effect speed/intensity: {:.1f}\n".format(patch[0]/25.5))
    fp.write ("\n")

    fp.write ("  Patch byte #: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f\n")
    fp.write ("                -----------------------------------------------\n")
    fp.write ("Raw patch data: ")
    fp.write ("{0[0]:02x} {0[1]:02x} {0[2]:02x} {0[3]:02x} ".format(patch))
    fp.write ("{0[4]:02x} {0[5]:02x} {0[6]:02x} {0[7]:02x} ".format(patch))
    fp.write ("{0[8]:02x} {0[9]:02x} {0[10]:02x} {0[11]:02x} ".format(patch))
    fp.write ("{0[12]:02x} {0[13]:02x} {0[14]:02x} {0[15]:02x}\n".format(patch))

def hexdump(patches, outfile):
    with open(outfile, 'wb') as f:
        for patch in patches:
            for byte in patch:
                f.write(struct.pack('B', byte))

def asciihexdump(patches):
    ctr = 0
    for patch in patches:
        print ("Patch " + PNAMES[ctr])
        for byte in patch:
            print ("{:02x} ".format(byte), end="")
        print ("\n\n", end="")
        ctr += 1

def textdump(patches, outfile):
    with open(outfile, 'w') as f:
        ctr = 0
        for patch in patches:
            f.write ("Patch " + PNAMES[ctr] + "\n")
            f.write ("=========\n");
            printpatch(patch, f)
            f.write ("\n\n")
            ctr += 1

def main(args):
    # Open file and maybe print some stats about it
    try:
        (fp, params) = fileopen(args['<infile>'])
    except FileNotFoundError as fnf:
        sys.stderr.write("Error: {} not found!\n".format(args['<infile>']))
        exit(1)
    if args['-v']:
        print ("Opened WAV file " + args['<infile>'])
        print ("Input file has {} channel{} @ {} Hz".format(
            params.nchannels,
            "s" if params.nchannels >1 else "",
            params.framerate))
        print ("{} frames of width {} each".format(
            params.nframes, params.sampwidth))

    # Extract samples from file with any conversion necessary
    if args['-v']:
        print ("Extracting and converting samples from file...")
    data = getdata(fp, params)

    # Find first byte after any silence and leader tone
    if args['-v']:
        print ("Finding start of data...")
    startidx = findstart(data, params)

    # Header should be 0x50 0x36
    if args['-v']:
        print ("Checking for Korg header...")
    (hdr1, length) = readbyte(data, startidx, params)
    idx = startidx + length
    (hdr2, length) = readbyte(data, idx, params)
    idx += length
    if hdr1 != 0x50 or hdr2 != 0x36:
        sys.stderr.write("Error: Tape header mismatch! Aborting.")
        exit(1)

    # Read 32 patches from file
    if args['-v']:
        print ("Reading 32 patches from file...")
    (patches, length) = readnpatches(data, idx, 32, params)
    idx += length

    # Read and verify checksum
    if args['-v']:
        print ("Reading and validating checksum...")
    (tapecksum, length) = readbyte(data, idx, params)
    cksum = checksum(patches)
    if tapecksum != cksum:
        sys.stderr.write("Warning: checksum mismatch!")
        sys.stderr.write(
            "Tape checksum: {:#04x}  Calculated checksum: {:#04x}".format(
              tapecksum, cksum))

    # Output to hex or text file as desired
    if args['--text']:
        if args['-v']:
            print ("Writing as text to file " + args['<outfile>'] + "...")
        textdump(patches, args['<outfile>'])
    elif '--hexconsole' in args and args['--hexconsole']:
        if args['-v']:
            print ("Writing as ASCII hex to console...")
        asciihexdump(patches)
    else:
        if args['-v']:
            print ("Writing as hex to file " + args['<outfile>'] + "...")
        hexdump(patches, args['<outfile>'])

    if args['-v']:
        print ("Done!")


if __name__ == "__main__":
    args = docopt.docopt(__doc__, version="1.0")
    main(args)
