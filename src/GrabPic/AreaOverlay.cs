using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Bitmap = System.Drawing.Bitmap;

namespace GrabPic;

public sealed class AreaOverlay : Window
{
    private readonly SelectionSurface surface;
    private readonly System.Drawing.Rectangle bounds;
    private System.Drawing.Point physicalStart;
    private Point start, latest;
    private bool dragging, pending;
    private long queuedAt, firstFrame, lastFrame;
    private TimeSpan lastRenderTime = TimeSpan.MinValue;
    private int moves, frames;
    private double maxQueueMs, maxDrawMs;
    private readonly List<double> gaps = new();
    public System.Drawing.Rectangle? Selected { get; private set; }

    public AreaOverlay(Bitmap frozen, System.Drawing.Rectangle screenBounds)
    {
        bounds = screenBounds;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; Topmost = true;
        ShowInTaskbar = false; Cursor = Cursors.Cross; Background = Brushes.Black;
        surface = new SelectionSurface(ImageSource(frozen)); Content = surface;
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            // Only the settings window uses the compatibility renderer; capture uses WPF's GPU path.
            HwndSource.FromHwnd(handle).CompositionTarget.RenderMode = RenderMode.Default;
            SetWindowPos(handle, new IntPtr(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x0040);
        };
        Loaded += (_, _) => { Activate(); Focus(); CompositionTarget.Rendering += RenderSelection; };
        MouseLeftButtonDown += (_, e) =>
        {
            Native.GetCursorPos(out physicalStart); start = latest = e.GetPosition(surface);
            dragging = true; CaptureMouse(); QueueSelection();
        };
        MouseMove += (_, e) => { if (dragging) { latest = e.GetPosition(surface); moves++; QueueSelection(); } };
        MouseLeftButtonUp += (_, _) =>
        {
            if (!dragging) return;
            dragging = false; ReleaseMouseCapture(); Native.GetCursorPos(out var end);
            var selected = System.Drawing.Rectangle.Intersect(bounds, System.Drawing.Rectangle.FromLTRB(
                Math.Min(physicalStart.X, end.X), Math.Min(physicalStart.Y, end.Y),
                Math.Max(physicalStart.X, end.X), Math.Max(physicalStart.Y, end.Y)));
            if (selected.Width >= 2 && selected.Height >= 2) Selected = selected;
            Close();
        };
        KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
        Closed += (_, _) => { CompositionTarget.Rendering -= RenderSelection; if (IsMouseCaptured) ReleaseMouseCapture(); WriteMetrics(); };
    }

    private void QueueSelection() { if (!pending) queuedAt = Stopwatch.GetTimestamp(); pending = true; }
    private void RenderSelection(object? sender, EventArgs args)
    {
        if (!pending || !dragging) return;
        if (args is RenderingEventArgs rendering) { if (rendering.RenderingTime == lastRenderTime) return; lastRenderTime = rendering.RenderingTime; }
        pending = false; long now = Stopwatch.GetTimestamp();
        maxQueueMs = Math.Max(maxQueueMs, Stopwatch.GetElapsedTime(queuedAt, now).TotalMilliseconds);
        if (firstFrame == 0) firstFrame = now;
        if (lastFrame != 0) gaps.Add(Stopwatch.GetElapsedTime(lastFrame, now).TotalMilliseconds);
        lastFrame = now; frames++;
        surface.Select(new Rect(start, latest));
        maxDrawMs = Math.Max(maxDrawMs, Stopwatch.GetElapsedTime(now).TotalMilliseconds);
    }

    public static BitmapSource ImageSource(Bitmap image)
    {
        // One direct pixel copy replaces PNG compression followed by PNG decompression.
        var area = new System.Drawing.Rectangle(0, 0, image.Width, image.Height);
        var pixels = image.LockBits(area, ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        try
        {
            var bitmap = BitmapSource.Create(image.Width, image.Height, 96, 96, PixelFormats.Bgr32, null,
                pixels.Scan0, checked(pixels.Stride * image.Height), pixels.Stride);
            bitmap.Freeze(); return bitmap;
        }
        finally { image.UnlockBits(pixels); }
    }

    private void WriteMetrics()
    {
        var path = Environment.GetEnvironmentVariable("GRABPIC_OVERLAY_METRICS");
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            gaps.Sort();
            File.WriteAllText(path, JsonSerializer.Serialize(new
            {
                RenderTier = RenderCapability.Tier >> 16, OverlayRenderMode = "Default",
                ScreenWidth = bounds.Width, ScreenHeight = bounds.Height, PointerMoves = moves, SelectionFrames = frames,
                AverageSelectionUpdatesPerSecond = frames > 1 ? (frames - 1) / Stopwatch.GetElapsedTime(firstFrame, lastFrame).TotalSeconds : 0,
                P95UpdateIntervalMs = gaps.Count > 0 ? gaps[Math.Min(gaps.Count - 1, (int)(gaps.Count * .95))] : 0,
                MaxQueuedUpdateMs = maxQueueMs, MaxDrawingSubmissionMs = maxDrawMs,
                SelectedWidth = Selected?.Width, SelectedHeight = Selected?.Height
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (IOException) { }
    }
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
}

// The desktop image and dimming stay retained. Dragging changes only this small visual, without layout.
internal sealed class SelectionSurface : FrameworkElement
{
    private readonly DrawingVisual backdrop = new(), selection = new(), hint = new();
    private readonly BitmapSource screenshot;
    private readonly Brush dim = Frozen(new SolidColorBrush(Color.FromArgb(115, 10, 9, 22)));
    private readonly Pen outline = new(Brushes.White, 1);
    public SelectionSurface(BitmapSource screenshot)
    {
        this.screenshot = screenshot; outline.Freeze();
        AddVisualChild(backdrop); AddVisualChild(selection); AddVisualChild(hint);
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.NearestNeighbor);
        SizeChanged += (_, _) => DrawBackdrop();
    }
    protected override int VisualChildrenCount => 3;
    protected override Visual GetVisualChild(int index) => index switch { 0 => backdrop, 1 => selection, 2 => hint, _ => throw new ArgumentOutOfRangeException(nameof(index)) };
    protected override HitTestResult HitTestCore(PointHitTestParameters parameters) => new PointHitTestResult(this, parameters.HitPoint);
    private void DrawBackdrop()
    {
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        var desktop = new Rect(0, 0, ActualWidth, ActualHeight);
        using (var draw = backdrop.RenderOpen()) { draw.DrawImage(screenshot, desktop); draw.DrawRectangle(dim, null, desktop); }
        using var instructions = hint.RenderOpen();
        instructions.DrawRoundedRectangle(Frozen(new SolidColorBrush(Color.FromRgb(35, 32, 48))), null, new Rect(28, 28, 350, 44), 9, 9);
        var text = new FormattedText("Drag to capture an area   ·   Esc to cancel", System.Globalization.CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight, new Typeface("Segoe UI"), 14, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        instructions.DrawText(text, new Point(44, 40));
    }
    public void Select(Rect area)
    {
        using var draw = selection.RenderOpen();
        if (area.Width < 1 || area.Height < 1) return;
        var clip = new RectangleGeometry(area); clip.Freeze();
        draw.PushClip(clip); draw.DrawImage(screenshot, new Rect(0, 0, ActualWidth, ActualHeight)); draw.Pop();
        draw.DrawRectangle(null, outline, area);
    }
    private static Brush Frozen(Brush brush) { brush.Freeze(); return brush; }
}
