// wavetables are from the open source Synthesis Technology WaveEdit editor
// See Engine_Wavetables for the thin Crone wiring

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

  // Slices the three banks into 195 wavetable-format signals
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
      // Duplicate of wave 1 at slot 64, so wave = 64 still reads wave 1
      out = out.add(
        Signal.newFrom(frames.copyRange(0, waveLen - 1)).asWavetable
      );
    });

    ^out;
  }

  // Allocates 195 consecutive buffers and fills them
  *loadBanks { arg server, dir;
    var wts = this.bankWavetables(dir);
    var bufs = Buffer.allocConsecutive(this.totalSlots, server, waveLen * 2, 1);
    server.sync;
    wts.do({ arg wt, i; bufs[i].sendCollection(wt, 0, 0.002) });
    server.sync;
    ^bufs;
  }

  // One phase source, shaped arithmetically. phase is added to the ramp
  // rather than passed as LFSaw's iphase, which is read only at synth start
  // and would ignore later lfo spread and osc spread changes.
  *lfo { arg rate, phase, shape;
    var ramp = (LFSaw.kr(rate).range(0, 1) + phase).wrap(0, 1);
    ^Select.kr(shape, [
      sin(ramp * 2pi),
      (ramp * 4 - 2).fold(-1, 1),
      (ramp * 2) - 1,
      1 - (ramp * 2),
      ((ramp < 0.5) * 2) - 1,
      LFNoise1.kr(rate)
    ]);
  }

  // Variable-slope lowpass, 6 to 24 dB/oct continuous
  *ladder { arg in, cutoff, slopeIdx;
    var coef = exp(-2pi * cutoff * SampleDur.ir).clip(0, 0.9999);
    var t1 = OnePole.ar(in, coef);
    var t2 = OnePole.ar(t1, coef);
    var t3 = OnePole.ar(t2, coef);
    var t4 = OnePole.ar(t3, coef);
    var taps = [t1, t2, t3, t4];
    var idx = slopeIdx.clip(0, 3);
    var lo = idx.floor;
    var frac = idx - lo;
    ^(Select.ar(lo, taps) * (1 - frac)) + (Select.ar((lo + 1).min(3), taps) * frac);
  }

  *synthDef {
    ^SynthDef(\wtvoice, {
      arg out = 0, bufOffset = 0, voiceIdx = 0,
          wave = 0, waveLag = 0.02,
          hz = 220, hzLag = 0.005, detune = 0,
          lfoRate = 0.1, lfoDepth = 0, lfoShape = 0,
          lfoSpread = 0, oscSpread = 0,
          cutoff = 20000, slopeIdx = 3,
          smplRate = 48000, bitDepth = 24,
          ampAtk = 0.001, ampRel = 0.05, envBias = 1.0,
          envDelay = 0.0, envDelayRand = 0.0,
          vol = 0.0, ampSlew = 0.01, pan = 0.0, panLag = 0.005;

      var hz_, vol_, pan_, base, voiceMorphPhase, oscs, sum, crushed, filt, amp_;
      var declick;

      hz_  = Lag.ar(K2A.ar(hz), hzLag);
      vol_ = Lag.ar(K2A.ar(vol), ampSlew);
      pan_ = Lag.ar(K2A.ar(pan), panLag);

      base = Lag.kr(wave, waveLag);

      // Lagged so turning lfo spread or osc spread glides the morph
      // position instead of stepping it
      lfoSpread = Lag.kr(lfoSpread, 0.1);
      oscSpread = Lag.kr(oscSpread, 0.1);

      voiceMorphPhase = (voiceIdx / numVoices) * lfoSpread;

      declick = EnvGen.kr(
        Env([1, 0, 1], [0.003, 0.005], \sine),
        gate: Changed.kr(bufOffset)
      );

      oscs = 3.collect({ arg k;
        var oscMorphPhase, rate, pos, f;

        // oscSpread fans the three oscillators across the morph sweep: up to a
        // third of an LFO cycle apart, with their LFO rates skewed by up to 3%
        // so the fan keeps sliding instead of settling into a fixed offset.
        // Both terms land in pos, the buffer index, so spread only changes which
        // wavetable each oscillator reads. It never reaches f; pitch is detune's
        // job alone, and these are morph-LFO phases, not audio phase.
        // Audio phase stays 0 for all three, so the swell is not beating: they
        // read different waves at any instant and their harmonics reinforce and
        // cancel by turns, thinning and filling the voice over minutes.
        oscMorphPhase = (k / 3) * oscSpread;
        rate = lfoRate * (1 + ((k - 1) * 0.03 * oscSpread));

        // VOsc sweeps every table between one block's position and the next
        pos = (base + (lfoDepth * WavetablesVoice.lfo(
          rate, voiceMorphPhase + oscMorphPhase, lfoShape))).fold(0, wavesPerBank);

        f = hz_ * (2 ** (((k - 1) * detune) / 1200));

        VOsc.ar(bufOffset + pos, f, 0, 1/3)
      });

      sum = Mix(oscs);

      crushed = Decimator.ar(sum, smplRate, bitDepth, 1.0, 0);

      filt = WavetablesVoice.ladder(crushed, cutoff, slopeIdx);

      amp_ = EnvGen.ar(
        Env.circle([0, 1, 0, 0], [ampAtk, ampRel, envDelay + envDelayRand]),
        levelBias: envBias
      );

      Out.ar(out, Pan2.ar(
        DelayN.ar(filt * amp_ * vol_, 0.01, 0.003) * declick, pan_));
    });
  }

  *outputDef {
    // Each voice peaks near full scale on its own, so 16 of them need
    // headroom before the limiter
    ^SynthDef(\wtoutput, { arg in = 0, out = 0, gain = 0.25;
      var sig = In.ar(in, 2) * gain;
      sig = Limiter.ar(sig, 1.0, 0.01);
      Out.ar(out, sig);
    });
  }
}
