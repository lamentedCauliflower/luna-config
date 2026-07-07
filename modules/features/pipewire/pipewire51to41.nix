{ ... }:
{
  flake.nixosModules.pipewire-5_1-to-4_1 = {
    services.pipewire.extraConfig.pipewire."30-5_1-to-4_1-Mixer" =
      let
        crossoverFreq = 200.0;
      in
      {
        "context.modules" = [
          {
            name = "libpipewire-module-filter-chain";
            args = {
              "node.description" = "5.1 to 4.1 crossover sink also swaps SL and SR";
              "media.name" = "5.1 to 4.1 crossover sink";
              "filter.graph" = {
                nodes = [
                  {
                    name = "inFL";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "inFR";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "inFC";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "inLFE";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "inSL";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "inSR";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "outFL";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "outFR";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "outSL";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "outSR";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "outLFE";
                    type = "builtin";
                    label = "copy";
                  }
                  {
                    name = "hpFL";
                    type = "builtin";
                    label = "bq_highpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "hpFR";
                    type = "builtin";
                    label = "bq_highpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "hpFC";
                    type = "builtin";
                    label = "bq_highpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "hpSL";
                    type = "builtin";
                    label = "bq_highpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "hpSR";
                    type = "builtin";
                    label = "bq_highpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpFL";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpFR";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpFC";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpLFE";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpSL";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "lpSR";
                    type = "builtin";
                    label = "bq_lowpass";
                    control = {
                      "Freq" = crossoverFreq;
                    };
                  }
                  {
                    name = "mixFL";
                    type = "builtin";
                    label = "mixer";
                    control = {
                      "Gain 1" = 1.0;
                      "Gain 2" = 0.5;
                    };
                  }
                  {
                    name = "mixFR";
                    type = "builtin";
                    label = "mixer";
                    control = {
                      "Gain 1" = 1.0;
                      "Gain 2" = 0.5;
                    };
                  }
                  {
                    name = "mixLFE";
                    type = "builtin";
                    label = "mixer";
                    control = {
                      "Gain 1" = 0.16666667;
                      "Gain 2" = 0.16666667;
                      "Gain 3" = 0.16666667;
                      "Gain 4" = 0.16666667;
                      "Gain 5" = 0.16666667;
                      "Gain 6" = 0.16666667;
                    };
                  }
                ];
                links = [
                  {
                    output = "inFL:Out";
                    input = "hpFL:In";
                  }
                  {
                    output = "inFR:Out";
                    input = "hpFR:In";
                  }
                  {
                    output = "inFC:Out";
                    input = "hpFC:In";
                  }
                  {
                    output = "inSL:Out";
                    input = "hpSL:In";
                  }
                  {
                    output = "inSR:Out";
                    input = "hpSR:In";
                  }

                  {
                    output = "hpFL:Out";
                    input = "mixFL:In 1";
                  }
                  {
                    output = "hpFR:Out";
                    input = "mixFR:In 1";
                  }
                  {
                    output = "hpFC:Out";
                    input = "mixFL:In 2";
                  }
                  {
                    output = "hpFC:Out";
                    input = "mixFR:In 2";
                  }
                  {
                    output = "hpSL:Out";
                    input = "outSR:In";
                  }
                  {
                    output = "hpSR:Out";
                    input = "outSL:In";
                  }

                  {
                    output = "mixFL:Out";
                    input = "outFL:In";
                  }
                  {
                    output = "mixFR:Out";
                    input = "outFR:In";
                  }

                  {
                    output = "inFL:Out";
                    input = "lpFL:In";
                  }
                  {
                    output = "inFR:Out";
                    input = "lpFR:In";
                  }
                  {
                    output = "inFC:Out";
                    input = "lpFC:In";
                  }
                  {
                    output = "inLFE:Out";
                    input = "lpLFE:In";
                  }
                  {
                    output = "inSL:Out";
                    input = "lpSL:In";
                  }
                  {
                    output = "inSR:Out";
                    input = "lpSR:In";
                  }

                  {
                    output = "lpFL:Out";
                    input = "mixLFE:In 1";
                  }
                  {
                    output = "lpFR:Out";
                    input = "mixLFE:In 2";
                  }
                  {
                    output = "lpFC:Out";
                    input = "mixLFE:In 3";
                  }
                  {
                    output = "lpLFE:Out";
                    input = "mixLFE:In 4";
                  }
                  {
                    output = "lpSL:Out";
                    input = "mixLFE:In 5";
                  }
                  {
                    output = "lpSR:Out";
                    input = "mixLFE:In 6";
                  }

                  {
                    output = "mixLFE:Out";
                    input = "outLFE:In";
                  }
                ];
                inputs = [
                  "inFL:In"
                  "inFR:In"
                  "inFC:In"
                  "inLFE:In"
                  "inSL:In"
                  "inSR:In"
                ];
                outputs = [
                  "outFL:Out"
                  "outFR:Out"
                  "outSL:Out"
                  "outSR:Out"
                  "outLFE:Out"
                ];
              };
              "capture.props" = {
                "node.name" = "effect_input.5.1_to_4.1";
                "media.class" = "Audio/Sink";
                "audio.channels" = 6;
                "audio.position" = [
                  "FL"
                  "FR"
                  "FC"
                  "LFE"
                  "SL"
                  "SR"
                ];
              };
              "playback.props" = {
                "node.name" = "effect_output.5.1_to_4.1";
                "node.passive" = true;
                "stream.dont-remix" = true;
                "audio.channels" = 5;
                "audio.position" = [
                  "FL"
                  "FR"
                  "SL"
                  "SR"
                  "LFE"
                ];
                "node.target" = "alsa_output.usb-Generic_CUBILUX_CA7-00.analog-surround-51";
              };
            };
          }
        ];
      };
  };

}
