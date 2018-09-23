/**
Copyright: Guillaume Piolat 2015-2017.
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
import std.math;
import dplug.core, dplug.client, dplug.vst;

version (unittest)
{}
else
{
    // This create the DLL entry point
    mixin(DLLEntryPoint!());

    // This create the VST entry point
    mixin(VSTEntryPoint!SimpleDelay);
}

enum size_t maxChannels = 2;

enum : int
{
    paramOnOff,
    paramDelayTimeSecondL,
    paramDelayTimeSecondR,
    paramDelayDryWetRatio,
    paramDelayFeedbackRatio,
}

auto floatValue(scope const Parameter p) nothrow @nogc
{
    if (auto f = cast(FloatParameter) p)
    {
        return f.value();
    }
    assert(false);
}

/// Simplest VST plugin you could make.
final class SimpleDelay : dplug.client.Client
{
public:
    import ringbuffer;
    RingBuffer!float[2] _buffer;

    enum float maxDelayTimeSecond = 10;
    double _sampleRate;
    size_t[maxChannels] _currentDelayTimeFrame;

    @property maxDelayTimeFrame() nothrow @nogc
    {
        return cast(size_t) (this.sampleRate * this.maxDelayTimeSecond);
    }

    @property sampleRate() nothrow @nogc
    {
        assert(!this._sampleRate.isNaN);
        return this._sampleRate;
    }

    @property delayTimeSecond(size_t ch)() nothrow @nogc
    {
        static assert(ch < maxChannels);
        return this.param(paramDelayTimeSecondL + ch).floatValue;
    }

    @property delayTimeFrame(size_t ch)() nothrow @nogc
    {
        return cast(size_t) (this.delayTimeSecond!ch * this.sampleRate);
    }
        
    @property delayDryWetRatio() nothrow @nogc
    {
        return this.param(paramDelayDryWetRatio).floatValue;
    }

    @property delayFeedbackRatio() nothrow @nogc
    {
        return this.param(paramDelayFeedbackRatio).floatValue;
    }

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo 
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        params.pushBack( mallocNew!BoolParameter(paramOnOff, "on/off", true) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayTimeSecondL,
                                                        "L-ch second", "",
                                                        0.0, maxDelayTimeSecond, 0.1) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayTimeSecondR,
                                                        "R-ch second", "",
                                                        0.0, maxDelayTimeSecond, 0.1) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayDryWetRatio,
                                                        "dry/wet ratio", "",
                                                        0.0, 1.0, 0.5) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayFeedbackRatio,
                                                        "feedback ratio", "",
                                                        0.0, 1.0, 0.0) );
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    override int latencySamples(double sampleRate) nothrow @nogc
    {
        return 0;
        // return cast(int) (maxDelayTimeSecond * this.sampleRate);
    }

    override float tailSizeInSeconds() nothrow @nogc
    {
        return fmax(this.delayTimeSecond!0, this.delayTimeSecond!1);
    }
    
    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        if (this._sampleRate != sampleRate)
        {
            this._sampleRate = sampleRate;
            this._buffer[0] = RingBuffer!float(this.maxDelayTimeFrame);
            this._buffer[1] = RingBuffer!float(this.maxDelayTimeFrame);
            this.resetInterval();
        }
    }

    void resetInterval() nothrow @nogc
    {
        static foreach (ch; 0..maxChannels)
        {{
            const f = this.delayTimeFrame!ch;
            if (f != this._currentDelayTimeFrame[ch])
            {
                this._buffer[ch].setInterval(f);
                this._currentDelayTimeFrame[ch] = f;
            }
        }}
    }    

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        const r = this.delayDryWetRatio;
        const fbk = this.delayFeedbackRatio;
        
        float[2] b;
        if (readBoolParamValue(paramOnOff))
        {
            foreach (t; 0 .. frames)
            {
                this.resetInterval();
                foreach (ch; 0 .. 2)
                {
                    b[ch] = this._buffer[ch].front;
                    this._buffer[ch].pushBack(inputs[ch][t] + b[ch] * fbk);
                    outputs[ch][t] = ((1.0 - r) * inputs[ch][t] + r * b[ch]) * SQRT1_2;
                    this._buffer[ch].popFront();
                }
            }
        }
        else // bypass
        {
            static foreach (ch; 0..2)
                outputs[ch][0..frames] = inputs[ch][0..frames];
        }
    }
}
