// wavetables: the DSP.
//
// Derived from sines (https://github.com/aidanreilly/sines), which took its
// voice architecture from catfact's zebra. Apache 2.0.
//
// Wavetables are the ROM banks of the Synthesis Technology E350 Morphing
// Terrarium, https://synthtech.com/eurorack/E350/ . See lib/waves/README.md.
//
// This class deliberately has no CroneEngine dependency, so a plain sclang
// can load it and the tests under test/sc can measure the real DSP.
// Engine_Wavetables is thin Crone wiring over this.

WavetablesVoice {
  classvar <numVoices = 16;
  classvar <wavesPerBank = 64;
  classvar <slotsPerBank = 65;   // see bankWavetables for the extra slot
  classvar <numBanks = 3;
  classvar <waveLen = 256;
  classvar <bankFiles;

  *initClass {
    bankFiles = ["rom_a.wav", "rom_b.wav", "rom_c.wav"];
  }

  *totalSlots { ^numBanks * slotsPerBank }

  *bankOffset { arg base, bank;
    ^base + ((bank.clip(1, numBanks) - 1) * slotsPerBank);
  }

  // Slices the three banks into 195 wavetable-format Signals.
  //
  // Language-side only, with no server involved, which is what makes it
  // testable. SoundFile reads the WAVs directly and avoids sequencing
  // asynchronous server buffer reads.
  //
  // Each 64-wave bank gets a 65th slot holding a copy of wave 1. VOsc
  // interpolates buf[n] against buf[n+1], so without that slot morph
  // position 63.5 would blend this bank's last wave with the next bank's
  // first, and a cycling LFO would stall or jump at the top of the bank.
  *bankWavetables { arg dir;
    var out = Array.new(this.totalSlots);

    bankFiles.do({ arg name;
      var path = dir ++ name;
      var frames = FloatArray.newClear(wavesPerBank * waveLen);
      var sf = SoundFile.openRead(path);

      if (sf.isNil) {
        Error("wavetables: cannot open" + path).throw;
      };
      if (sf.numFrames != (wavesPerBank * waveLen)) {
        var n = sf.numFrames;
        sf.close;
        Error("wavetables:" + name + "has" + n + "frames, expected"
          + (wavesPerBank * waveLen)).throw;
      };
      sf.readData(frames);
      sf.close;

      wavesPerBank.do({ arg w;
        out = out.add(
          Signal.newFrom(
            frames.copyRange(w * waveLen, ((w + 1) * waveLen) - 1)
          ).asWavetable
        );
      });
      // the duplicate wave 1 that makes the morph wrap
      out = out.add(
        Signal.newFrom(frames.copyRange(0, waveLen - 1)).asWavetable
      );
    });

    ^out;
  }

  // Allocates 195 consecutive buffers and fills them. VOsc requires the
  // buffers be consecutively numbered and identically sized.
  *loadBanks { arg server, dir;
    var wts = this.bankWavetables(dir);
    var bufs = Buffer.allocConsecutive(this.totalSlots, server, waveLen * 2, 1);
    server.sync;
    wts.do({ arg wt, i; bufs[i].sendCollection(wt) });
    server.sync;
    ^bufs;
  }
}
