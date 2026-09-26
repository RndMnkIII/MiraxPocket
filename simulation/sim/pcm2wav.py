#!/usr/bin/env python3
# pcm2wav.py - wrap raw mono s16le PCM (from tb_questa) into a .wav
#   python3 pcm2wav.py frames/audio.pcm [rate] [out.wav]
#   default rate 48000 (matches +AUDIO_DIV=1000 on a 48 MHz design clock)
import sys, os, wave

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: pcm2wav.py <audio.pcm> [rate=48000] [out.wav]")
    src  = sys.argv[1]
    rate = int(sys.argv[2]) if len(sys.argv) > 2 else 48000
    out  = sys.argv[3] if len(sys.argv) > 3 else os.path.splitext(src)[0] + ".wav"
    data = open(src, "rb").read()
    if len(data) & 1:                      # keep sample alignment
        data = data[:-1]
    w = wave.open(out, "wb")
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes(data); w.close()
    print(f"wrote {out}  ({len(data)//2} samples, {rate} Hz, "
          f"{len(data)/2/rate:.2f}s)")

if __name__ == "__main__":
    main()
