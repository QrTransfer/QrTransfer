using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace QrSender.Windows;

internal sealed class SenderForm : Form
{
    private readonly Label status = new() { Dock = DockStyle.Fill, AutoEllipsis = true, Height = 44, Margin = new Padding(0, 8, 0, 4) };
    private readonly Button open = new() { Text = "Open…", AutoSize = true };
    private readonly Button play = new() { Text = "Play", AutoSize = true, Enabled = false };
    private readonly ComboBox mode = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
    private readonly NumericUpDown fps = new() { Minimum = 2, Maximum = 20, Value = 8, Width = 54 };
    private readonly TrackBar block = new() { Minimum = 4, Maximum = 30, Value = 14, TickStyle = TickStyle.None, Width = 140, AutoSize = false, Height = 28 };
    private readonly Label blockLabel = new() { AutoSize = true, Width = 86 };
    private readonly QrPreview preview = new() { Dock = DockStyle.Fill };
    private readonly System.Windows.Forms.Timer timer = new();
    private TransferFile? file;
    private FountainEncoder? encoder;
    private long shown;
    private bool loading;
    private string? error;

    private bool IsColor => mode.SelectedIndex == 1;
    private int BlockSize => block.Value * 50;

    public SenderForm()
    {
        Text = "QrSender";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(680, 730);
        MinimumSize = new Size(470, 430);
        StartPosition = FormStartPosition.CenterScreen;

        mode.Items.AddRange(["Mono", "Color ×3"]);
        mode.SelectedIndex = 1;
        mode.AccessibleName = "QR code mode";
        fps.AccessibleName = "Frames per second";
        block.AccessibleName = "Block size";
        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true };
        toolbar.Controls.AddRange([open, play, mode, ToolbarLabel("FPS"), fps, blockLabel, block]);
        blockLabel.Margin = new Padding(8, 8, 0, 0);

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Padding = new Padding(16) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(preview, 0, 0);
        layout.Controls.Add(status, 0, 1);
        layout.Controls.Add(toolbar, 0, 2);
        Controls.Add(layout);

        open.Click += async (_, _) => await ChooseFileAsync();
        play.Click += (_, _) => TogglePlayback();
        timer.Tick += (_, _) => Advance();
        fps.ValueChanged += (_, _) =>
        {
            timer.Interval = (int)Math.Round(1000 / (double)fps.Value);
            UpdateStatus();
        };
        timer.Interval = 125;
        mode.SelectedIndexChanged += (_, _) => Advance();
        block.ValueChanged += (_, _) => ResetEncoder();

        foreach (Control control in new Control[] { this, layout, toolbar, preview, status, open, play, mode, fps, blockLabel, block })
        {
            control.AllowDrop = true;
            control.DragEnter += (_, e) => e.Effect = !loading && DroppedFile(e) != null
                ? DragDropEffects.Copy : DragDropEffects.None;
            control.DragDrop += async (_, e) =>
            {
                if (DroppedFile(e) is { } path)
                    await LoadFileAsync(path);
            };
        }

        ResetEncoder();
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == (Keys.Control | Keys.O))
        {
            open.PerformClick();
            return true;
        }
        if (keyData == Keys.Space && play.Enabled)
        {
            TogglePlayback();
            return true;
        }

        return base.ProcessCmdKey(ref msg, keyData);
    }

    private static Label ToolbarLabel(string text) =>
        new() { Text = text, AutoSize = true, Margin = new Padding(8, 8, 0, 0) };

    private static string? DroppedFile(DragEventArgs e) =>
        e.Data?.GetData(DataFormats.FileDrop) is string[] { Length: 1 } paths && File.Exists(paths[0])
            ? paths[0] : null;

    private async Task ChooseFileAsync()
    {
        using var dialog = new OpenFileDialog { Title = "Open a file to send", Filter = "All files|*.*" };
        bool wasPlaying = timer.Enabled;
        timer.Stop();
        if (dialog.ShowDialog(this) == DialogResult.OK)
            await LoadFileAsync(dialog.FileName, wasPlaying);
        else
            SetPlayback(wasPlaying);
    }

    private async Task LoadFileAsync(string path, bool resumeOnError = false)
    {
        if (loading)
            return;

        bool wasPlaying = resumeOnError || timer.Enabled;
        SetPlayback(false);
        loading = true;
        open.Enabled = play.Enabled = mode.Enabled = fps.Enabled = block.Enabled = false;
        error = null;
        UpdateStatus();

        try
        {
            var loaded = await Task.Run(() => TransferFile.Read(path));
            if (!IsDisposed)
                file = loaded;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            error = ex.Message;
        }
        finally
        {
            if (!IsDisposed)
            {
                loading = false;
                open.Enabled = mode.Enabled = fps.Enabled = block.Enabled = true;
                play.Enabled = encoder != null || file != null;
                if (error == null)
                    ResetEncoder();
                else
                {
                    SetPlayback(wasPlaying);
                    UpdateStatus();
                }
            }
        }
    }

    private void ResetEncoder()
    {
        blockLabel.Text = $"Block {BlockSize} B";
        if (file != null)
        {
            encoder = new FountainEncoder(file, BlockSize);
            shown = 0;
            error = null;
        }
        Advance();
    }

    private void TogglePlayback() => SetPlayback(!timer.Enabled);

    private void SetPlayback(bool playing)
    {
        timer.Enabled = playing && encoder != null;
        play.Text = timer.Enabled ? "Pause" : "Play";
    }

    private void Advance()
    {
        if (encoder != null)
        {
            preview.SetFrame(new QrFrame(encoder, IsColor));
            shown++;
        }
        UpdateStatus();
    }

    private void UpdateStatus()
    {
        status.ForeColor = error == null ? SystemColors.ControlText : Color.Firebrick;
        if (loading)
            status.Text = "Preparing file…";
        else if (error != null)
            status.Text = error;
        else if (file != null && encoder != null)
        {
            double seconds = encoder.BlockCount * 1.2 / ((int)fps.Value * (IsColor ? 3 : 1));
            string compression = file.Compressed ? " · compressed" : "";
            status.Text = $"{file.Name} · {file.Size:N0} bytes{compression}\n" +
                $"{shown:N0} shown · {encoder.BlockCount:N0} blocks · ≈{seconds:N0} s";
        }
        else
            status.Text = "No file";
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            timer.Dispose();
        base.Dispose(disposing);
    }
}

internal sealed class QrPreview : Control
{
    private QrFrame? frame;
    private Bitmap? bitmap;
    private byte[] pixels = [];
    private bool dirty;

    public QrPreview()
    {
        BackColor = Color.White;
        DoubleBuffered = true;
        ResizeRedraw = true;
        AccessibleName = "QR code preview";
    }

    public void SetFrame(QrFrame value)
    {
        frame = value;
        dirty = true;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (frame == null)
        {
            TextRenderer.DrawText(e.Graphics, "Drop a file here or click Open…", Font, ClientRectangle,
                SystemColors.GrayText, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
            return;
        }

        int side = Math.Min(1200, Math.Min(ClientSize.Width, ClientSize.Height));
        if (side == 0)
            return;

        var square = new Rectangle(0, 0, side, side);
        if (bitmap?.Width != side)
        {
            bitmap?.Dispose();
            bitmap = new Bitmap(side, side, PixelFormat.Format32bppRgb);
            pixels = new byte[side * side * 4];
            dirty = true;
        }
        if (dirty)
        {
            frame.Rasterize(side, pixels);
            var data = bitmap!.LockBits(square, ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
            try
            {
                Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
            dirty = false;
        }

        e.Graphics.DrawImageUnscaled(bitmap, (Width - side) / 2, (Height - side) / 2);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
            bitmap?.Dispose();
        base.Dispose(disposing);
    }
}
