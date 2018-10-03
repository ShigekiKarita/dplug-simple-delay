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
    import dplug.pbrwidgets : UILabel;
    import dplug.client :
        IGraphics, PluginInfo, TimeInfo, LegalIO,
        parsePluginInfo, LinearFloatParameter, BoolParameter;

    import ringbuffer : RingBuffer;
    import gui : SimpleGUI;

public:

    // audio related
    RingBuffer!float[2] _buffer;
    enum float maxDelayTimeSecond = 10;
    double _sampleRate;
    size_t[maxChannels] _currentDelayTimeFrame;
    int _numInputs = 2;

    // GUI related
    SimpleGUI gui;
    UILabel[EnumMembers!Param.length] labels;
    char[100][this.labels.length] labelData;

    // NOTE: this method will not call until GUI required (lazy)
    override IGraphics createGraphics() @nogc nothrow
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
        this.labels[Param.onOff] = this.gui.addLabel("", pos);
        int x = this.gui.marginW + this.gui.kW;
        foreach (i; Param.delayDryWetRatio .. Param.delayTimeSecondR + 1)
        {
            auto p = box2i.rectangle(x, this.gui.marginH,
                                     this.gui.kW, this.gui.marginH + 20);
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

    override PluginInfo buildPluginInfo() nothrow @nogc
    {
        // Plugin info is parsed from plugin.json here at compile time.
        // Indeed it is strongly recommended that you do not fill PluginInfo
        // manually, else the information could diverge.
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override Parameter[] buildParameters() nothrow @nogc
    {
        // WARNING: this order depends on enum Param member order
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

    override LegalIO[] buildLegalIO() nothrow @nogc
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(1, 2));
        io.pushBack(LegalIO(2, 2));
        return io.releaseData();
    }
    
    override float tailSizeInSeconds() nothrow @nogc
    {
        return fmax(this.delayTimeSecond!0, this.delayTimeSecond!1);
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) nothrow @nogc
    {
        this._numInputs = numInputs;
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

    void updateText(string fmt, Param i)() nothrow @nogc
    {
        auto s = snFormat!fmt(this.labelData[i], readFloatParamValue(i));
        this.labels[i].text(cast(string) s);
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info) nothrow @nogc
    {
        immutable isOn = readBoolParamValue(Param.onOff);
        with (Param) // update GUI
        {
            if (this.gui) {
                this.labels[onOff].text(isOn ? "ON" : "OFF");
                this.updateText!("%6.2f", delayDryWetRatio);
                this.updateText!("%6.2f", delayFeedbackRatio);
                this.updateText!("%6.2f sec", delayTimeSecondL);
                this.updateText!("%6.2f sec", delayTimeSecondR);
            }
        }

        immutable r = readFloatParamValue(Param.delayDryWetRatio);
        if (isOn) // apply effect
        {
            immutable fbk = readFloatParamValue(Param.delayFeedbackRatio);
            this.resetInterval();
            foreach (t; 0 .. frames)
            {
                foreach (och; 0 .. outputs.length)
                {
                    immutable ich = och < this._numInputs ? och : 0;
                    immutable b = this._buffer[och].front;
                    immutable i = (1.0 - r) * inputs[ich][t];
                    immutable o = i + r * b; //  * SQRT1_2;
                    outputs[och][t] = o;
                    this._buffer[och].popFront();
                    this._buffer[och].pushBack(i + b * r * fbk);
                }
            }
        }
        else // bypass
        {
            foreach (och; 0.. outputs.length)
            {
                immutable ich = och < this._numInputs ? och : 0;
                outputs[och][0..frames] = r * inputs[ich][0..frames];
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
