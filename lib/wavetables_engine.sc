// wavetables: norns engine wiring.
//
// All DSP lives in WavetablesVoice, which has no Crone dependency so it can
// be tested off hardware. This file is only the Crone glue and the command
// surface, and is the one part of the engine that cannot be tested locally.

Engine_Wavetables : CroneEngine {
  classvar numVoices = 16;

  var <synths, <bus, <outputStage, <bufs, <wtBase;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  // Where our own source file lives, so nothing hardcodes a norns path.
  wavePath {
    ^PathName(this.class.filenameSymbol.asString).pathOnly ++ "waves/";
  }

  alloc {
    // context.server, not Crone.server: context is the CroneAudioContext
    // this engine was handed and already supplies xg and out_b. Reaching
    // for the Crone classvar instead adds a way for alloc to throw on its
    // first Buffer call and hang the script at load.
    var server = context.server;

    bufs = WavetablesVoice.loadBanks(server, this.wavePath);

    // Buffer.allocConsecutive posts "No more buffer numbers" and returns an
    // incomplete result when 195 consecutive bufnums are not free. Without
    // this the next line fails on a nil, inside a Routine, with nothing
    // naming the real cause. norns' buffer count is the one unknown the
    // design never closed, so say the number out loud.
    if (bufs.isNil or: { bufs.size != WavetablesVoice.totalSlots }) {
      Error("wavetables: needed" + WavetablesVoice.totalSlots
        + "consecutive buffers, got" + bufs.size.asString
        + "- raise scsynth's -b setting").throw;
    };

    wtBase = bufs[0].bufnum;
    server.sync;

    WavetablesVoice.synthDef.add;
    WavetablesVoice.outputDef.add;
    server.sync;

    bus = Bus.audio(server, 2);
    server.sync;

    synths = Array.fill(numVoices, { arg i;
      Synth.new(\wtvoice, [
        \out, bus,
        \voiceIdx, i,
        \bufOffset, WavetablesVoice.bankOffset(wtBase, 1)
      ], target: context.xg);
    });
    server.sync;

    // target: context.xg, so the output stage sits at the tail of the same
    // group as the voices. Omitting target resolves to
    // Server.default.defaultGroup, which is either a different server (the
    // node is never created and the engine is silent with no error) or the
    // tail of group 1, after norns' own output group, which reads out_b a
    // block before we write it.
    outputStage = Synth.new(\wtoutput,
      [\in, bus, \out, context.out_b],
      target: context.xg, addAction: \addToTail);
    server.sync;

    this.addCommands;
  }

  addCommands {
    // Per-voice float params, set straight onto the synth by name.
    [
      [\vol, \vol], [\hz, \hz], [\pan, \pan],
      [\wave, \wave], [\detune, \detune],
      [\lfo_rate, \lfoRate], [\lfo_depth, \lfoDepth],
      [\lfo_shape, \lfoShape],
      [\cutoff, \cutoff], [\slope_idx, \slopeIdx],
      [\amp_atk, \ampAtk], [\amp_rel, \ampRel], [\env_bias, \envBias],
      [\env_delay, \envDelay], [\env_delay_rand, \envDelayRand],
      [\amp_slew, \ampSlew], [\hz_lag, \hzLag],
      [\pan_lag, \panLag], [\wave_lag, \waveLag]
    ].do({ arg pair;
      var cmd = pair[0], argName = pair[1];
      this.addCommand(cmd, "if", { arg msg;
        var i = msg[1].asInteger;
        if ((i >= 0) and: { i < numVoices }) {
          synths[i].set(argName, msg[2]);
        };
      });
    });

    // Bank is an index 1 to 3; the engine owns the bufnum arithmetic so the
    // Lua side never sees buffer numbers.
    this.addCommand(\bank, "ii", { arg msg;
      var i = msg[1].asInteger;
      if ((i >= 0) and: { i < numVoices }) {
        synths[i].set(\bufOffset,
          WavetablesVoice.bankOffset(wtBase, msg[2].asInteger));
      };
    });

    [[\smpl_rate, \smplRate], [\bit_depth, \bitDepth]].do({ arg pair;
      var cmd = pair[0], argName = pair[1];
      this.addCommand(cmd, "ii", { arg msg;
        var i = msg[1].asInteger;
        if ((i >= 0) and: { i < numVoices }) {
          synths[i].set(argName, msg[2].asInteger);
        };
      });
    });

    // Voice gating. A silent voice still costs three oscillators, four
    // filter stages and a decimator, so the Lua side parks it.
    this.addCommand(\voice_run, "ii", { arg msg;
      var i = msg[1].asInteger;
      if ((i >= 0) and: { i < numVoices }) {
        synths[i].run(msg[2].asInteger > 0);
      };
    });

    // Globals, applied to every voice. Each voice scales them by its own
    // voiceIdx, so one value produces 16 different phase offsets.
    [[\lfo_spread, \lfoSpread], [\vco_drift, \vcoDrift]].do({ arg pair;
      var cmd = pair[0], argName = pair[1];
      this.addCommand(cmd, "f", { arg msg;
        synths.do({ arg s; s.set(argName, msg[1]) });
      });
    });
  }

  free {
    if (synths.notNil) { synths.do({ arg s; s.free }) };
    if (outputStage.notNil) { outputStage.free };
    if (bus.notNil) { bus.free };
    if (bufs.notNil) { bufs.do({ arg b; b.free }) };
  }
}
