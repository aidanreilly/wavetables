// wavetables: norns engine wiring
//
// All DSP lives in WavetablesVoice, which has no Crone dependency

Engine_Wavetables : CroneEngine {
  classvar numVoices = 16;

  var <synths, <bus, <outputStage, <bufs, <wtBase;
  var posVoice = 0, lastPos = -1, posFunc;

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

    // The voice with report = 1 sends its morph position here; the
    // wave_pos poll hands the latest one to Lua for drawing. -1 means no
    // position yet, or the voice is parked and not sending, and Lua falls
    // back to the wave param.
    // nodeID check drops a reply still in flight from the previous voice.
    posFunc = OSCFunc({ arg msg;
      if (msg[1] == synths[posVoice].nodeID) { lastPos = msg[3] };
    }, '/wavetables/pos');
    synths[posVoice].set(\report, 1);

    outputStage = Synth.new(\wtoutput,
      [\in, bus, \out, context.out_b],
      target: context.xg, addAction: \addToTail);
    server.sync;

    this.addCommands;
    this.addPoll(\wave_pos, { lastPos });
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
        if (i == posVoice) { lastPos = -1 };
      };
    });

    // Which voice reports its morph position to the wave_pos poll.
    this.addCommand(\pos_voice, "i", { arg msg;
      var i = msg[1].asInteger;
      if ((i >= 0) and: { i < numVoices } and: { i != posVoice }) {
        synths[posVoice].set(\report, 0);
        synths[i].set(\report, 1);
        posVoice = i;
        lastPos = -1;
      };
    });

    [[\lfo_spread, \lfoSpread], [\osc_spread, \oscSpread]].do({ arg pair;
      var cmd = pair[0], argName = pair[1];
      this.addCommand(cmd, "f", { arg msg;
        synths.do({ arg s; s.set(argName, msg[1]) });
      });
    });
  }

  free {
    if (posFunc.notNil) { posFunc.free };
    if (synths.notNil) { synths.do({ arg s; s.free }) };
    if (outputStage.notNil) { outputStage.free };
    if (bus.notNil) { bus.free };
    if (bufs.notNil) { bufs.do({ arg b; b.free }) };
  }
}
