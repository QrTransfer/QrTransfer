using System.Collections;
using QRCoder;

namespace QrSender.Windows;

internal sealed class QrFrame
{
    private readonly List<BitArray>[] channels;

    public QrFrame(FountainEncoder encoder, bool color)
    {
        channels = new List<BitArray>[color ? 3 : 1];
        for (int channel = 0; channel < channels.Length; channel++)
        {
            using var qr = QRCodeGenerator.GenerateQrCode(encoder.Next(), QRCodeGenerator.ECCLevel.L);
            channels[channel] = qr.ModuleMatrix;
        }
    }

    // Format32bppRgb stores blue, green, red and an unused byte, in that order.
    public void Rasterize(int side, byte[] pixels)
    {
        Array.Fill(pixels, (byte)255);
        for (int channel = 0; channel < channels.Length; channel++)
        {
            var matrix = channels[channel];
            int modules = matrix.Count;
            int scale = side / modules;
            if (scale == 0)
                continue;

            int margin = (side - modules * scale) / 2;
            for (int y = 0; y < modules; y++)
            for (int x = 0; x < modules; x++)
            {
                if (!matrix[y][x])
                    continue;

                int start = ((margin + y * scale) * side + margin + x * scale) * 4;
                for (int row = 0; row < scale; row++)
                for (int col = 0; col < scale; col++)
                {
                    int pixel = start + (row * side + col) * 4;
                    if (channels.Length == 1)
                        pixels[pixel] = pixels[pixel + 1] = pixels[pixel + 2] = 0;
                    else
                        pixels[pixel + 2 - channel] = 0;
                }
            }
        }
    }
}
