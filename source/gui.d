/**
Copyright: Shigeki Karita
License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/
module gui;

import dplug.pbrwidgets : PBRBackgroundGUI;

class SimpleDelayGUI : PBRBackgroundGUI!("black.png", "black.png", "black.png",
                                         "black.png", "black.png", "black.png",
                                         "")
{
public nothrow @nogc:
    import gfm.math : box2i;
    import dplug.core : mallocNew, destroyFree;
    import dplug.gui : PBRCompositor;
    import dplug.pbrwidgets : Font, RGBA, UIKnob, UILabel;
    import dplug.client : Parameter, FloatParameter;
    import main : Param;
    
    Font _font;

    this(Parameter[] parameters...)
    {
        _font = mallocNew!Font(cast(ubyte[])( import("VeraBd.ttf") ));
        super(620, 200); // size

        PBRCompositor comp = cast(PBRCompositor)compositor;
        RGBA litTrailDiffuse = RGBA(151, 119, 255, 100);
        RGBA unlitTrailDiffuse = RGBA(81, 54, 108, 0);

        int marginW=10;
        int marginH=10;
        const n = cast(int) parameters.length;
        int w, h;
        this.getGUISize(&w, &h);
        const kW = (w - 2 * marginW) / n;
        const kH = h - 2 * marginH;
        foreach (int i, param; parameters) {
            auto p = cast(FloatParameter) param;
            const x = marginW + kW * i;
                
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

            UILabel label;
            addChild(label = mallocNew!UILabel(context(), _font, p.name));
            label.position = box2i.rectangle(x, kH, kW, marginH);
            label.textColor(RGBA(200, 200, 200, 255));
        }
    }

    ~this()
    {
        _font.destroyFree();
    }
}


