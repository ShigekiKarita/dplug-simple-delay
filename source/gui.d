/**
Copyright: Shigeki Karita
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import dplug.pbrwidgets : PBRBackgroundGUI;


class SimpleGUI
    : PBRBackgroundGUI!("black.png", "black.png", "black.png",
                        "black.png", "black.png", "black.png",
                        "")
{
public nothrow @nogc:
    import gfm.math : box2i;
    import dplug.core : mallocNew, destroyFree;
    import dplug.pbrwidgets : Font, RGBA, UIKnob, UILabel, UIOnOffSwitch;
    import dplug.client : Parameter, FloatParameter, BoolParameter;
    
    Font _font;
    enum litTrailDiffuse = RGBA(151, 119, 255, 100);
    enum unlitTrailDiffuse = RGBA(81, 54, 108, 0);

    UILabel addLabel(string text, box2i rect) {
        UILabel label;
        addChild(label = mallocNew!UILabel(context(), _font, text));
        label.position = rect;
        label.textColor(RGBA(200, 200, 200, 255));
        return label;
    }
    
    const int marginW=10;
    const int marginH=10;
    const int kW, kH;

    this(Parameter[] parameters...)
    {
        _font = mallocNew!Font(cast(ubyte[])( import("VeraBd.ttf") ));
        super(620, 200); // size
        const n = cast(int) parameters.length;
        int w, h;
        this.getGUISize(&w, &h);
        kW = (w - 2 * marginW) / n;
        kH = h - 2 * marginH;
        int x = marginW;

        import std.traits;
        foreach (param; parameters) {
            if (auto p = cast(FloatParameter) param) {                
                UIKnob knob;
                addChild(knob = mallocNew!UIKnob(context(), p));
                knob.position = box2i.rectangle(x, marginH, kW, kH);
                knob.knobRadius = 0.65f;
                knob.knobDiffuse = RGBA(50, 50, 100, 0); // color of knob
                // NOTE: material [R(smooth), G(metal), B(shiny), A(phisycal)]
                knob.knobMaterial = RGBA(255, 255, 255, 255);
                knob.numLEDs = 0;
                knob.litTrailDiffuse = litTrailDiffuse;
                knob.unlitTrailDiffuse = unlitTrailDiffuse;
                knob.LEDDiffuseLit = RGBA(0, 0, 40, 100);
                knob.LEDDiffuseUnlit = RGBA(0, 0, 40, 0);
                knob.LEDRadiusMin = 0.06f;
                knob.LEDRadiusMax = 0.06f;
                addLabel(p.name, box2i.rectangle(x, kH, kW, marginH));
            }
            else if (auto p = cast(BoolParameter) param) {
                UIOnOffSwitch onOffSwitch;
                addChild(onOffSwitch = mallocNew!UIOnOffSwitch(context(), p));
                onOffSwitch.position = box2i.rectangle(x + (kW - 30) / 2,
                                                       marginH + (kH - 40) / 2,
                                                       30, 40);
                onOffSwitch.diffuseOn = litTrailDiffuse;
                onOffSwitch.diffuseOff = unlitTrailDiffuse;
                addLabel(p.name, box2i.rectangle(x, kH, kW, marginH));
            }
            else {
                continue; // ignore
            }
            x += kW;
        }
    }

    ~this()
    {
        _font.destroyFree();
    }
}


