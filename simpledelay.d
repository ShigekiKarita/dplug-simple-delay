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

enum : int
{
    paramOnOff, paramDelayTimeSecond, paramDelayRatio
}

/// Simplest VST plugin you could make.
final class SimpleDelay : dplug.client.Client
{
public:
    import ringbuffer;
    RingBuffer!float[2] _buffer;

    enum float maxDelayTimeSecond = 10;
    double _sampleRate;
    size_t _currentDelayTimeFrame;

    @property maxDelayTimeFrame() nothrow @nogc
    {
        return cast(size_t) (this.sampleRate * this.maxDelayTimeSecond);
    }

    @property sampleRate() nothrow @nogc
    {
        assert(!this._sampleRate.isNaN);
        return this._sampleRate;
    }

    @property delayTimeSecond() nothrow @nogc
    {
        const p = this.param(paramDelayTimeSecond);
        if (auto f = cast(FloatParameter) p) {
            return f.value();
        }
        assert(false);
    }

    @property delayTimeFrame() nothrow @nogc
    {
        return cast(size_t) (this.delayTimeSecond * this.sampleRate);
    }
        
    @property delayRatio() nothrow @nogc
    {
        const p = this.param(paramDelayRatio);
        if (auto f = cast(FloatParameter) p) {
            return f.value();
        }
        assert(false);
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
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayTimeSecond, "second", "",
                                                     0.0, maxDelayTimeSecond, 0.1) );
        params.pushBack( mallocNew!LinearFloatParameter(paramDelayRatio, "ratio", "",
                                                        0.0, 1.0, 0.5) );
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
        return cast(int) (maxDelayTimeSecond * this.sampleRate);
    }

    override float tailSizeInSeconds() nothrow @nogc
    {
        return this.delayTimeSecond;
    }
    
    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        if (this._sampleRate != sampleRate)
        {
            this._sampleRate = sampleRate;
            this._buffer[0] = RingBuffer!float(this.maxDelayTimeFrame);
            this._buffer[1] = RingBuffer!float(this.maxDelayTimeFrame);
            this._currentDelayTimeFrame = this.delayTimeFrame;
        }
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        const r = this.delayRatio;
        const f = this.delayTimeFrame;
        if (readBoolParamValue(paramOnOff))
        {
            foreach (t; 0 .. frames)
            {
                if (f != this._currentDelayTimeFrame)
                {
                    this._buffer[0].setInterval(f);
                    this._buffer[1].setInterval(f);
                    this._currentDelayTimeFrame = f;
                }
                outputs[0][t] = ((1.0 - r) * inputs[0][t] + r * this._buffer[0].front) * SQRT1_2;
                outputs[1][t] = ((1.0 - r) * inputs[1][t] + r * this._buffer[1].front) * SQRT1_2;
                this._buffer[0].popFront();
                this._buffer[1].popFront();
                this._buffer[0].pushBack(inputs[0][t]);
                this._buffer[1].pushBack(inputs[1][t]);
            }
        }
        else // bypass
        {
            static foreach (ch; 0..2)
                outputs[ch][0..frames] = inputs[ch][0..frames];
        }
    }
}
