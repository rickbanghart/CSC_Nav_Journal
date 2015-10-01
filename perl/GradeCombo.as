package Components {
    import fl.controls.ComboBox;
    import flash.display.Shape;
    import flash.text.TextField;
    import flash.text.TextLineMetrics;
    import flash.text.TextFieldAutoSize;
    import flash.text.TextFormat;
    public class GradeCombo extends Sprite {
        public var confirmation = false;
        public function GradeCombo(width:Number,height:Number,border:uint,fill:uint) {
            var combo:ComboBox = new ComboBox();
            var comboLabel:TextField = new TextField();
            comboLabel.defaultTextFormat = titleFormat;
            comboLabel.autoSize = TextFieldAutoSize.LEFT;
            comboLabel.text = "Grade";
            comboLabel.width = 40;
            comboLabel.y = 5;
            var myTextFormat:TextFormat = new TextFormat();
            myTextFormat.align = "center";
            myTextFormat.font = "Arial";
            myTextFormat.size = 12;
            myTextFormat.bold = true;
            myTextFormat.color = 0x000000;
            //combo.textField.setStyle("textFormat", myTextFormat);
            //combo.dropdown.setStyle("cellRenderer",ComboCellRenderer);
            combo.addItem({label:"K", data:0});
            combo.addItem({label:"1", data:1});
            combo.addItem({label:"2", data:2});
            combo.addItem({label:"3", data:3});
            combo.addItem({label:"4", data:4});
            combo.addItem({label:"5", data:5});
            combo.addItem({label:"6", data:6});
            combo.addItem({label:"7", data:7});
            combo.addItem({label:"8", data:8});
            //combo.prompt = "Grade";
            combo.addEventListener(Event.CHANGE, gradeSelected);
            combo.y = 5;
            combo.x = comboLabel.width + 5;
            combo.width = 50;
            combo.selectedIndex = 0;
            combo.rowCount = combo.length;
            combo.name = "gradeCombo";
            //combo.setStyle("textFormat",buttonTextFormat);
            addChild(combo);
            addChild(comboLabel);
        }
    }
}