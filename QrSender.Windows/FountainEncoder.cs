using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;

namespace QrSender.Windows;

internal sealed record TransferFile(string Name, int Size, byte[] Payload, bool Compressed, string Sha256)
{
    public static TransferFile Read(string path)
    {
        var data = File.ReadAllBytes(path);
        var digest = Convert.ToHexStringLower(SHA256.HashData(data));
        var payload = data;
        if (data.Length > 0)
        {
            // Apple's NSData .zlib uses raw DEFLATE on the wire.
            using var compressed = new MemoryStream();
            using (var stream = new DeflateStream(compressed, CompressionLevel.Fastest, leaveOpen: true))
                stream.Write(data);

            if (compressed.Length < data.Length)
                payload = compressed.ToArray();
        }

        return new TransferFile(Path.GetFileName(path), data.Length, payload, payload != data, digest);
    }
}

internal sealed class FountainEncoder
{
    private const int MetadataInterval = 10;
    private const int MaxDegree = 100;
    private readonly TransferFile file;
    private readonly int blockSize;
    private readonly double[] degrees;
    private readonly string prefix;
    private readonly string metadataFrame;
    private int frameInCycle;

    public int BlockCount { get; }

    public FountainEncoder(TransferFile file, int blockSize)
    {
        this.file = file;
        this.blockSize = blockSize;
        BlockCount = Math.DivRem(file.Payload.Length, blockSize, out int remainder) + (remainder == 0 ? 0 : 1);
        degrees = DegreeDistribution(BlockCount);
        prefix = $"QRT2|{Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4))}|";
        var metadata = JsonSerializer.SerializeToUtf8Bytes(new
        {
            name = file.Name,
            size = file.Size,
            z = file.Compressed,
            sha256 = file.Sha256,
            k = BlockCount,
            b = blockSize,
            len = file.Payload.Length
        });
        metadataFrame = prefix + "M|" + Convert.ToBase64String(metadata);
    }

    public string Next()
    {
        bool sendMetadata = frameInCycle == 0 || BlockCount == 0;
        frameInCycle = (frameInCycle + 1) % MetadataInterval;
        if (sendMetadata)
            return metadataFrame;

        double sample = Random.Shared.NextDouble() * degrees[^1];
        int degree = Array.FindIndex(degrees, threshold => sample < threshold) + 1;
        var indices = new SortedSet<int>();
        while (indices.Count < degree)
            indices.Add(Random.Shared.Next(BlockCount));

        var block = new byte[blockSize];
        foreach (int index in indices)
        {
            int start = index * blockSize;
            int count = Math.Min(blockSize, file.Payload.Length - start);
            for (int offset = 0; offset < count; offset++)
                block[offset] ^= file.Payload[start + offset];
        }

        string indexList = string.Join(",", indices.Select(index => index.ToString(CultureInfo.InvariantCulture)));
        return prefix + "D|" + indexList + "|" + Convert.ToBase64String(block);
    }

    private static double[] DegreeDistribution(int blockCount)
    {
        if (blockCount == 0)
            return [];

        // Match the macOS sender's robust soliton distribution (c = 0.03, delta = 0.5).
        double r = 0.03 * Math.Log(blockCount / 0.5) * Math.Sqrt(blockCount);
        var thresholds = new double[Math.Min(blockCount, MaxDegree)];
        int pivot = Math.Clamp((int)(blockCount / r), 1, thresholds.Length);
        double total = 0;
        for (int degree = 1; degree <= thresholds.Length; degree++)
        {
            double rho = degree == 1 ? 1.0 / blockCount : 1.0 / (degree * (degree - 1));
            double tau = degree < pivot ? r / (degree * (double)blockCount)
                : degree == pivot ? r * Math.Log(r / 0.5) / blockCount : 0;
            total += rho + Math.Max(0, tau);
            thresholds[degree - 1] = total;
        }

        return thresholds;
    }
}
