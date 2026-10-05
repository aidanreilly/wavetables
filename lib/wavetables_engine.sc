// wavetables: norns engine wiring
//
// All DSP lives in WavetablesVoice, which has no Crone dependency

Engine_Wavetables : CroneEngine {
  classvar numVoices = 16;

  var <synths, <bus, <outputStage, <bufs, <wtBase;

  *new { arg context, doneCallback;
    ^super.new(context, doneCallback);
  }

  wavePath {
    ^PathName(this.class.filenameSymbol.asString).pathOnly ++ "waves/";
  }

  alloc {
    var server = context.server;

    bufs = WavetablesVoice.loadBanks(server, this.wavePath);

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

    // Voice gating. Keep silent voices from eating CPU
    this.addCommand(\voice_run, "ii", { arg msg;
      var i = msg[1].asInteger;
      if ((i >= 0) and: { i < numVoices }) {
        synths[i].run(msg[2].asInteger > 0);
      };
    });

    [[\lfo_spread, \lfoSpread], [\osc_drift, \oscDrift]].do({ arg pair;
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
