using System.Collections.Specialized;
using System.Windows;
using System.Windows.Media.Imaging;

namespace BetterScreenshot.Platform;

/// <summary>
/// Clipboard interactions. <see cref="SetImage"/> puts both the bitmap and a file-drop of a temp PNG on the
/// clipboard (so it can be pasted as an image or dropped as a file), then deletes the temp file once the user's
/// retention window elapses (see <see cref="TempFiles.PayloadLifetime"/>). Must be called on an STA thread (the
/// WPF UI thread at runtime).
/// </summary>
public static class ClipboardService
{
    public static void SetImage(BitmapSource image)
    {
        string tempPng = ImageIo.WriteTempPng(image, "clipboard.png");
        var data = new DataObject();
        data.SetImage(image);
        data.SetFileDropList(new StringCollection { tempPng });
        Clipboard.SetDataObject(data, copy: true);
        TempFiles.ScheduleDeleteContainingDir(tempPng, TempFiles.PayloadLifetime);
    }

    public static void SetText(string text) => Clipboard.SetText(text);

    /// <summary>Puts a single existing file on the clipboard as a file-drop (e.g. a saved recording).</summary>
    public static void SetFile(string path)
    {
        var data = new DataObject();
        data.SetFileDropList(new StringCollection { path });
        Clipboard.SetDataObject(data, copy: true);
    }
}
