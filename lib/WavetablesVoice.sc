// wavetables: the DSP.
//
// Derived from sines (https://github.com/aidanreilly/sines), which took its
// voice architecture from catfact's zebra. Apache 2.0.
//
// The wavetables are the open source set used in Synthesis Technology VCO
// eurorack modules, distributed with their WaveEdit editor,
// https://synthtech.com/waveedit/ . See lib/waves/README.md.
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
  // The 2 ms wait paces the 195 b_setn messages.
  //
  // sendCollection rather than loadCollection, which the design originally
  // specified: loadCollection goes via a temp file per buffer, and 195 temp
  // file writes on a Pi's SD card is a worse trade than a 0.4 s pause. The
  // pacing is there because 195 unpaced ~2 KB OSC messages back to back is
  // the shape that overflows a socket buffer, and a dropped b_setn leaves
  // one wavetable silently zeroed. All 195 are read back and compared by
  // test_load_banks_round_trips_through_a_live_server.
  //
  // Needs to run inside a Routine for the wait, which norns' engine load
  // and the test's waitForBoot both provide.
  *loadBanks { arg server, dir;
    var wts = this.bankWavetables(dir);
    var bufs = Buffer.allocConsecutive(this.totalSlots, server, waveLen * 2, 1);
    server.sync;
    wts.do({ arg wt, i; bufs[i].sendCollection(wt, 0, 0.002) });
    server.sync;
    ^bufs;
  }

  // One phase source, shaped arithmetically.
  //
  // SC's LFO UGens disagree on phase units (SinOsc radians, LFTri 0 to 4,
  // LFSaw 0 to 2, LFPulse none at all), which would break the lfoSpread and
  // vcoDrift phase fans the moment the shape changed. So the phase is
  // defined exactly once, by LFSaw, whose iphase spans 0 to 2 for a full
  // cycle. Hence the * 2 on the incoming 0 to 1 phase.
  //
  // Control rate throughout: the morph updates once per 64-sample block,
  // which VOsc then ramps across the block. Measured, not assumed.
  *lfo { arg rate, phase, shape;
    var ramp = LFSaw.kr(rate, phase * 2).range(0, 1);
    ^Select.kr(shape, [
      sin(ramp * 2pi),
      (ramp * 4 - 2).fold(-1, 1),
      (ramp * 2) - 1,
      1 - (ramp * 2),
      ((ramp < 0.5) * 2) - 1,
      LFNoise1.kr(rate)
    ]);
  }

  // Variable-slope lowpass, 6 to 24 dB/oct continuous.
  //
  // Four one-poles in series with the four taps crossfaded. Measured at
  // cutoff 100 Hz across the octave 800 to 1600 Hz: -5.96, -11.82, -17.90
  // and -23.87 dB/oct, agreeing with an independent Python model to within
  // 0.09 dB.
  //
  // OnePole takes a coefficient, not Hz. The conversion runs at control
  // rate: 16 exp calls per block across the engine rather than 1024.
  //
  // There is no resonance, deliberately. A LocalIn/LocalOut feedback path
  // around this cascade was built and measured: the one-block delay is
  // 1.33 ms, which at 1 kHz is 1.33 cycles of phase, so the feedback
  // arrives uncorrelated with the filter's own phase response. The result
  // was +0.00 dB of resonance at 4 kHz and above, or self-oscillation at
  // every cutoff at or above 1 kHz once the feedback gain passed 1.25. No
  // setting was usable. This cascade is purely feedforward and therefore
  // cannot have gain above unity or diverge at any cutoff.
  // The tap crossfade is LINEAR, not SelectX.
  //
  // SelectX is an equal-power crossfade, which is right for decorrelated
  // sources. These four taps are the same signal filtered successively, so
  // they are highly correlated, and equal-power weights summing to sqrt(2)
  // give up to +3 dB at a fractional slope setting. Measured: white noise
  // at 0.5 came out at 0.71 peak with slopeIdx 1.5 and cutoff 20 kHz.
  // Linear weights sum to 1, so the level holds across the knob and the
  // cascade keeps its guarantee of no gain above unity. It also matches
  // test/model/ladder.py, which crossfades linearly, so the oracle and the
  // engine now agree at fractional settings and not just integer ones.
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
          lfoSpread = 0, vcoDrift = 0,
          cutoff = 20000, slopeIdx = 3,
          smplRate = 48000, bitDepth = 24,
          ampAtk = 0.001, ampRel = 0.05, envBias = 1.0,
          envDelay = 0.0, envDelayRand = 0.0,
          vol = 0.0, ampSlew = 0.01, pan = 0.0, panLag = 0.005;

      var hz_, vol_, pan_, base, voicePhase, oscs, sum, crushed, filt, amp_;
      var declick;

      hz_  = Lag.ar(K2A.ar(hz), hzLag);
      vol_ = Lag.ar(K2A.ar(vol), ampSlew);
      pan_ = Lag.ar(K2A.ar(pan), panLag);

      // Lagged so a bank change, a param jump or a preset recall glides
      // rather than clicking.
      base = Lag.kr(wave, waveLag);

      // fans the 16 voices apart so they do not morph in lockstep
      voicePhase = (voiceIdx / numVoices) * lfoSpread;

      // Bank changes click, so duck the voice across them. The trick is
      // that the audio is delayed and the trigger is not, which buys the
      // envelope enough lookahead to be closed before the glitch arrives.
      //
      // bufOffset jumps 65 buffers in one control block and the waveform
      // changes discontinuously. Measured without any of this, a B to C
      // change produced a sample jump of 1.34 against a 99.9th percentile
      // of 0.38. Lagging bufOffset is not the fix: it would sweep the read
      // position through all 65 intervening waves, a zipper rather than a
      // glide. Ducking after the trigger does not work either, because the
      // trigger and the discontinuity are simultaneous.
      //
      // Changed.kr fires a single-sample trigger when bufOffset moves, and
      // the envelope rests at 1 otherwise, so a voice that never changes
      // bank is untouched apart from DECLICK_DELAY of latency. 3 ms on a
      // drone voice is inaudible and uniform across all 16 voices.
      declick = EnvGen.kr(
        Env([1, 0, 1], [0.003, 0.005], \sine),
        gate: Changed.kr(bufOffset)
      );

      oscs = 3.collect({ arg k;
        var vcoPhase, rate, pos, f;

        // vcoDrift fans the three VCOs a third of a cycle apart and also
        // detunes their LFO rates slightly. The rate detune is what keeps a
        // held chord moving: unequal rates diverge and reconverge without
        // repeating. At 0 the three VCOs morph together.
        vcoPhase = (k / 3) * vcoDrift;
        rate = lfoRate * (1 + ((k - 1) * 0.03 * vcoDrift));

        // SC's % is a floored modulo, so a deep LFO wrapping below zero
        // lands back inside the bank with no guard.
        pos = (base + (lfoDepth * WavetablesVoice.lfo(
          rate, voicePhase + vcoPhase, lfoShape))) % wavesPerBank;

        f = hz_ * (2 ** (((k - 1) * detune) / 1200));

        // All three VCOs start at phase 0, and the mul of 1/3 is what keeps
        // detune 0 at single-oscillator level.
        //
        // An earlier design gave them offsets of 0, 2pi/3 and 4pi/3 to stop
        // them summing coherently. Those are the three cube roots of unity,
        // so at detune 0 they CANCEL: measured RMS fell from 0.21 to
        // 0.000025. Every other fixed offset set also recolours the timbre,
        // because at identical frequency each harmonic gets a different
        // phasor sum. Phase 0 is the only set that leaves the waveform
        // alone, and 1/3 already prevents the level jump the offsets were
        // added to avoid.
        //
        // Level does fall as detune opens up, from 0.71 at 0 cents to 0.44
        // at 50, because the three oscillators go from a coherent sum to an
        // incoherent one. That is what unison does, it is monotonic, and
        // test_detune_level_falls_smoothly_without_cancelling pins it.
        VOsc.ar(bufOffset + pos, f, 0, 1/3)
      });

      sum = Mix(oscs);

      // Bitcrush before the filter, so the ladder smooths the quantisation
      // noise and the slope control doubles as a grit control.
      crushed = Decimator.ar(sum, smplRate, bitDepth, 1.0, 0);

      filt = WavetablesVoice.ladder(crushed, cutoff, slopeIdx);

      amp_ = EnvGen.ar(
        Env.circle([0, 1, 0, 0], [ampAtk, ampRel, envDelay + envDelayRand]),
        levelBias: envBias
      );

      // DelayN by the declick envelope's fall time, so the discontinuity
      // reaches the output exactly when the gain has reached zero.
      Out.ar(out, Pan2.ar(
        DelayN.ar(filt * amp_ * vol_, 0.01, 0.003) * declick, pan_));
    });
  }

  *outputDef {
    ^SynthDef(\wtoutput, { arg in = 0, out = 0;
      var sig = In.ar(in, 2);
      sig = Limiter.ar(sig, 1.0, 0.01);
      Out.ar(out, sig);
    });
  }
}
