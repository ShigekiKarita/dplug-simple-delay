/**
Copyright: Shigeki Karita, 2018
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module simpledelay;

import dplug.client : Parameter, Client, DLLEntryPoint, FloatParameter;

version (unittest)
{}
else
{
    // This create the DLL entry point
    mixin(DLLEntryPoint!());

    // This create the VST entry point
    import dplug.vst;
    mixin(VSTEntryPoint!SimpleDelay);
}

enum size_t maxChannels = 2;

enum Param : int
{
    onOff,
    delayDryWetRatio,
    delayFeedbackRatio,
    delayTimeSecondL,
    delayTimeSecondR,
}


/// Simplest VST plugin you could make.
final class SimpleDelay : Client
{
    import std.traits : EnumMembers;
    import std.math : SQRT1_2, isNaN, fmax;
    import gfm.math : box2i;
    import dplug.core : mallocNew, makeVec; //, destroyFree;
    import dplug.client :
        IGraphics, PluginInfo, TimeInfo, LegalIO,
        parsePluginInfo, LinearFloatParameter, BoolParameter;

public:
    import ringbuffer;
    import gui : SimpleGUI;
    RingBuffer!float[2] _buffer;

    enum float maxDelayTimeSecond = 10;
    double _sampleRate;
    size_t[maxChannels] _currentDelayTimeFrame;
    SimpleGUI gui;
    import dplug.pbrwidgets : UILabel;
    UILabel[EnumMembers!Param.length] labels;

    bool isOn() @nogc nothrow
    {
        auto p = cast(BoolParameter) this.param(Param.onOff);
        assert(p);
        return p.value();
    }

    override IGraphics createGraphics()
    {
        this.gui = mallocNew!(SimpleGUI)(
            this.param(Param.onOff),
            this.param(Param.delayDryWetRatio),
            this.param(Param.delayFeedbackRatio),
            this.param(Param.delayTimeSecondL),
            this.param(Param.delayTimeSecondR)
        );
        auto pos = box2i.rectangle(this.gui.marginW,
                                   this.gui.marginH,
                                   this.gui.kW,
                                   this.gui.marginH + 20);
        this.labels[Param.onOff] = this.gui.addLabel(
            this.isOn ? "ON" : "OFF", pos);

        int x = this.gui.marginW + this.gui.kW;
        foreach (i; Param.delayDryWetRatio .. Param.delayTimeSecondR + 1)
        {
            auto p = box2i.rectangle(x,
                                     this.gui.marginH,
                                     this.gui.kW,
                                     this.gui.marginH + 20);
            this.labels[i] = this.gui.addLabel("", p);
            x += this.gui.kW;
        }
        return this.gui;
    }

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
        return readFloatParamValue(Param.delayTimeSecondL + ch);
    }

    @property delayTimeFrame(size_t ch)() nothrow @nogc
    {
        return cast(size_t) (this.delayTimeSecond!ch * this.sampleRate);
    }

    @property delayDryWetRatio() nothrow @nogc
    {
        return readFloatParamValue(Param.delayDryWetRatio);
    }

    @property delayFeedbackRatio() nothrow @nogc
    {
        return readFloatParamValue(Param.delayFeedbackRatio);
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
        params.pushBack( mallocNew!BoolParameter(Param.onOff, "on/off", true) );
        params.pushBack( mallocNew!LinearFloatParameter(Param.delayDryWetRatio,
                                                        "dry/wet ratio", "",
                                                        0.0, 1.0, 0.5) );
        params.pushBack( mallocNew!LinearFloatParameter(Param.delayFeedbackRatio,
                                                        "feedback ratio", "",
                                                        0.0, 1.0, 0.0) );
        params.pushBack( mallocNew!LinearFloatParameter(Param.delayTimeSecondL,
                                                        "L-ch second", "",
                                                        0.0, maxDelayTimeSecond, 0.1) );
        params.pushBack( mallocNew!LinearFloatParameter(Param.delayTimeSecondR,
                                                        "R-ch second", "",
                                                        0.0, maxDelayTimeSecond, 0.1) );
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(1, 2));
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }

    override int latencySamples(double sampleRate) nothrow @nogc
    {
        return 0;
    }

    override float tailSizeInSeconds() nothrow @nogc
    {
        return 0; // fmax(this.delayTimeSecond!0, this.delayTimeSecond!1);
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        if (this._sampleRate != sampleRate)
        {
            this._sampleRate = sampleRate;
            this._buffer[0] = RingBuffer!float(2 * this.maxDelayTimeFrame);
            this._buffer[1] = RingBuffer!float(2 * this.maxDelayTimeFrame);
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

    char[100][this.labels.length] labelData;

    void updateText(string fmt, Param i)()
    {
        import std.string;
        auto s = snFormat!fmt(this.labelData[i], readFloatParamValue(i));
        this.labels[i].text(cast(string) s);
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        this.resetInterval();
        immutable isOn = readBoolParamValue(Param.onOff);
        with (Param)
        {
            this.labels[onOff].text(isOn ? "ON" : "OFF");
            this.updateText!("%6.2f", delayDryWetRatio);
            this.updateText!("%6.2f", delayFeedbackRatio);
            this.updateText!("%6.2f sec", delayTimeSecondL);
            this.updateText!("%6.2f sec", delayTimeSecondR);
        }
        if (isOn)
        {
            float[maxChannels] b;
            const r = this.delayDryWetRatio;
            const fbk = this.delayFeedbackRatio;
            foreach (t; 0 .. frames)
            {
                foreach (ch; 0 .. outputs.length)
                {
                    const ich = ch > inputs.length ? 0 : ch;
                    b[ch] = this._buffer[ch].front;
                    this._buffer[ch].popFront();
                    auto o = ((1.0 - r) * inputs[ich][t] + r * b[ch]); //  * SQRT1_2;
                    outputs[ch][t] = o;
                    this._buffer[ch].pushBack(o + b[ch] * (r * fbk - r));
                }
            }
        }
        else // bypass
        {
            foreach (ch; 0.. outputs.length)
            {
                const ich = ch > inputs.length ? 0 : ch;
                outputs[ch][0..frames] = inputs[ich][0..frames];
            }
        }
    }
}


auto snFormat(string fmt="%6.2f", size_t N, T)(ref char[N] c, T v)
{
    import std.string;
    import core.stdc.stdio;
    snprintf(c.ptr, N, fmt, v);
    return c.ptr.fromStringz;
}

unittest
{
    import std.string;
    import std.stdio;
    char[7] c;
    assert(c.snFormat(1.23) == "  1.23");
    assert(c.snFormat(10.0) == " 10.00");
    c.snFormat(10.0).writeln;
}
