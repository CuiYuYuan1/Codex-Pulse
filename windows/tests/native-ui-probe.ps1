param(
    [ValidateSet("Info", "Hover", "HoverTopRight", "Click", "DoubleClick", "DesktopClick", "MoveCenter")]
    [string]$Action = "Info"
)

$signature = @"
using System;
using System.Runtime.InteropServices;

public static class NativeWindowProbe
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
"@

Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue
[NativeWindowProbe]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null

$process = Get-Process CodexPulse -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $process) {
    throw "CodexPulse main window was not found"
}

$rect = New-Object NativeWindowProbe+RECT
if (-not [NativeWindowProbe]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
    throw "GetWindowRect failed"
}

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
$scale = [NativeWindowProbe]::GetDpiForWindow($process.MainWindowHandle) / 96.0
$capsuleCenterX = $rect.Left + [Math]::Round($width / 2)
$capsuleCenterY = $rect.Top + [Math]::Round(48 * $scale)
$capsuleHoverX = $capsuleCenterX + [Math]::Round(105 * $scale)
$capsuleTopY = $rect.Top + [Math]::Round(16 * $scale)

switch ($Action) {
    "Hover" {
        [NativeWindowProbe]::SetCursorPos($capsuleHoverX, $capsuleCenterY) | Out-Null
    }
    "HoverTopRight" {
        [NativeWindowProbe]::SetCursorPos($capsuleCenterX + [Math]::Round(92 * $scale), $capsuleTopY) | Out-Null
    }
    "Click" {
        [NativeWindowProbe]::SetCursorPos($capsuleCenterX, $capsuleCenterY) | Out-Null
        Start-Sleep -Milliseconds 80
        [NativeWindowProbe]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [NativeWindowProbe]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    }
    "DoubleClick" {
        [NativeWindowProbe]::SetCursorPos($capsuleCenterX, $capsuleCenterY) | Out-Null
        Start-Sleep -Milliseconds 80
        1..2 | ForEach-Object {
            [NativeWindowProbe]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
            [NativeWindowProbe]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds 90
        }
    }
    "DesktopClick" {
        [NativeWindowProbe]::SetCursorPos(100, 100) | Out-Null
        Start-Sleep -Milliseconds 80
        [NativeWindowProbe]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [NativeWindowProbe]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    }
    "MoveCenter" {
        [NativeWindowProbe]::SetWindowPos($process.MainWindowHandle, [IntPtr]::Zero, 900, 520, 0, 0, 0x0015) | Out-Null
    }
}

[pscustomobject]@{
    ProcessId = $process.Id
    WindowLeft = $rect.Left
    WindowTop = $rect.Top
    WindowWidth = $width
    WindowHeight = $height
    ScaleFactor = $scale
    PointerX = if ($Action -eq "Hover") { $capsuleHoverX } elseif ($Action -eq "HoverTopRight") { $capsuleCenterX + [Math]::Round(92 * $scale) } else { $capsuleCenterX }
    PointerY = if ($Action -eq "HoverTopRight") { $capsuleTopY } else { $capsuleCenterY }
    Action = $Action
} | Format-List
