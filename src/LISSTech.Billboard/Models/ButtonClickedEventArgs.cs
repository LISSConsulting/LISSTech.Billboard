using System;
using LISSTech.Billboard.Models;

namespace LISSTech.Billboard.Controls;

public class ButtonClickedEventArgs : EventArgs
{
    public ButtonDefinition Button { get; }
    public int Index { get; }

    public ButtonClickedEventArgs(ButtonDefinition button, int index)
    {
        Button = button;
        Index  = index;
    }
}
