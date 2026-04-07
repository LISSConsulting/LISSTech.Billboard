using System.Windows;

namespace LISSTech.Billboard.Helpers;

public static class ScreenHelper
{
    public static Rect GetPrimaryWorkArea()
    {
        // SystemParameters.WorkArea is already in DIPs — no manual DPI conversion needed
        return SystemParameters.WorkArea;
    }

    public static void PositionBottomRight(Window window, double margin = 16)
    {
        var work = GetPrimaryWorkArea();
        window.Left = work.Right - window.Width - margin;
        window.Top = work.Bottom - window.Height - margin;
    }

}
