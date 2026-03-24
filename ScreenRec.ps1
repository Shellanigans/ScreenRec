Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class AviNative
{
    [DllImport("avifil32.dll")]
    public static extern void AVIFileInit();

    [DllImport("avifil32.dll")]
    public static extern void AVIFileExit();

    [DllImport("avifil32.dll", CharSet=CharSet.Ansi)]
    public static extern int AVIFileOpen(ref IntPtr ppfile, string szFile, uint uMode, IntPtr lpHandler);

    [DllImport("avifil32.dll")]
    public static extern int AVIFileCreateStream(IntPtr pfile, out IntPtr ppstream, ref AVISTREAMINFO psi);

    [DllImport("avifil32.dll")]
    public static extern int AVIMakeCompressedStream(out IntPtr ppsCompressed, IntPtr psSource, ref AVICOMPRESSOPTIONS lpOptions, IntPtr pclsidHandler);

    [DllImport("avifil32.dll")]
    public static extern int AVIStreamSetFormat(IntPtr pStream, int lPos, ref BITMAPINFOHEADER lpFormat, int cbFormat);

    [DllImport("avifil32.dll")]
    public static extern int AVIStreamWrite(IntPtr pStream, int lStart, int lSamples, IntPtr lpBuffer, int cbBuffer, int dwFlags, IntPtr plSampWritten, IntPtr plBytesWritten);

    [DllImport("avifil32.dll")]
    public static extern int AVIStreamRelease(IntPtr pstream);

    [DllImport("avifil32.dll")]
    public static extern int AVIFileRelease(IntPtr pfile);

    public const uint OF_CREATE = 0x00001000;
    public const uint OF_WRITE = 0x00000001;
    public const int AVIIF_KEYFRAME = 0x10;

    [StructLayout(LayoutKind.Sequential, Pack=1)]
    public struct BITMAPINFOHEADER
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public short biPlanes;
        public short biBitCount;
        public int biCompression;
        public int biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public int biClrUsed;
        public int biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential, Pack=1)]
    public struct AVISTREAMINFO
    {
        public int fccType;
        public int fccHandler;
        public int dwFlags;
        public int dwCaps;
        public short wPriority;
        public short wLanguage;
        public int dwScale;
        public int dwRate;
        public int dwStart;
        public int dwLength;
        public int dwInitialFrames;
        public int dwSuggestedBufferSize;
        public int dwQuality;
        public int dwSampleSize;
        public RECT rcFrame;
        public int dwEditCount;
        public int dwFormatChangeCount;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)]
        public string szName;
    }

    [StructLayout(LayoutKind.Sequential, Pack=1)]
    public struct AVICOMPRESSOPTIONS
    {
        public int fccType;
        public int fccHandler;
        public int dwKeyFrameEvery;
        public int dwQuality;
        public int dwBytesPerSecond;
        public int dwFlags;
        public IntPtr lpFormat;
        public int cbFormat;
        public IntPtr lpParams;
        public int cbParms;
        public int dwInterleaveEvery;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left, top, right, bottom;
    }
}
"@

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

function Select-ScreenRect {
    param(
        [switch]$fullScreen
    )

    $form = New-Object Windows.Forms.Form
    $form.WindowState = "Maximized"
    $form.FormBorderStyle = "None"
    $form.BackColor = [System.Drawing.Color]::Black
    $form.Opacity = 0.25
    $form.TopMost = $true
    $form.Cursor = [System.Windows.Forms.Cursors]::Cross
    #$form.DoubleBuffered = $true

    $form.Tag = @{
        start = $null
        rect = $null
    }
    $form.Add_MouseDown({
        $this.Tag.start = $_.Location
    })

    if(!$fullScreen){
        $form.Add_MouseMove({
            if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $this.Tag.start -ne $null) {
                $x = [Math]::Min($this.Tag.start.X, $_.X)
                $y = [Math]::Min($this.Tag.start.Y, $_.Y)
                $w = [Math]::Abs($_.X - $this.Tag.start.X)
                $h = [Math]::Abs($_.Y - $this.Tag.start.Y)

                $this.Tag.Rect = [System.Drawing.Rectangle]::new($x,$y,$w,$h)
                $this.Invalidate()
            }
        })

        $form.Add_Paint({
            if ($this.Tag.rect -ne $null) {
                try{
                    $pen = [Drawing.Pen]::new([Drawing.Color]::Red, 3)
                    $_.Graphics.DrawRectangle($pen, $this.Tag.rect)
                    $pen.Dispose()
                }catch{}
            }
        })

        $form.Add_MouseUp({
            $this.Close()
        })

        [void]$form.ShowDialog()
    }else{
        $form.Show()
        $form.Tag.rect = [System.Drawing.Rectangle]::new(0, 0, $form.Width, $form.Height)
        $form.Hide()
    }

    return $form.Tag.rect
}

function New-PropertyItem {
    param(
        $id,
        $type,
        $len,
        $val
    )
    $pic = [Drawing.Bitmap]::new(1,1)
    $stm = [System.IO.MemoryStream]::new()
    $pic.Save($stm, [System.Drawing.Imaging.ImageFormat]::Gif)
    $pic.Dispose()
    $stm.Position = 0
    $pic = [System.Drawing.Image]::FromStream($stm)
    $p = $pic.PropertyItems[0]
    $p.Id = $id
    $p.Type = $type
    $p.Len = $len
    $p.Value = $val
    $pic.Dispose()
    $stm.Dispose()
    return $p
}

function Record-ScreenGIF{
    param(
        [string]$outputFile = $(Join-Path (Get-Location) ("Recording_{0}.gif" -f (Get-Date -Format "yyyyMMdd_HHmmss"))),
        [int]$durationMs = 0,
        [int]$intervalMs = 250,
        [switch]$fullScreen
    )

    $rect = Select-ScreenRect -fullScreen:$fullScreen
    if($rect.Width -le 0 -or $rect.Height -le 0){return}

    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | ?{ $_.MimeType -eq "image/gif" } | Select -First 1
    $encoder = [System.Drawing.Imaging.Encoder]::SaveFlag
    $params = [System.Drawing.Imaging.EncoderParameters]::new(1)

    $tempFolder = Join-Path $env:TEMP ("rec_" + [guid]::NewGuid())
    [void](New-Item $tempFolder -ItemType Directory)

    if($durationMs -eq 0){
        Write-Host "Recording indefinitely; Press Ctrl+C to stop."
    }else{
        Write-Host "Recording for $durationMs milliseconds..."
    }

    try{
        for($i = 0; $i -lt [System.Math]::Floor(($durationMs/$intervalMs)) -or $durationMs -eq 0; $i++){
            $bmp = [System.Drawing.Bitmap]::new($rect.Width, $rect.Height)
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)

            $gfx.CopyFromScreen($rect.X, $rect.Y, 0, 0, $bmp.Size)

            $file = Join-Path $tempFolder ("img_{0:D6}.png" -f $i)
            $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::png)

            $gfx.Dispose()
            $bmp.Dispose()

            [System.Threading.Thread]::Sleep($intervalMs)
        }
    }catch{
        Write-Host -ForegroundColor Cyan $error[0]
    }finally{
        Write-Host "`nEncoding GIF..."

        $files = Get-ChildItem $tempFolder -Filter *.png | Sort-Object Name
        $images = $files | %{[System.Drawing.Image]::FromFile($_.FullName)}
        
        $delay = [Math]::Max([int]($intervalMs / 10),1)
        $delayBytes = [byte[]]::new((4 * $images.Count))
        for($i = 0; $i -lt $images.Count; $i++){
            [BitConverter]::GetBytes($delay).CopyTo($delayBytes, $i*4)
        }

        $propDelay = New-PropertyItem -id 0x5100 -type 4 -len $delayBytes.Length -val $delayBytes
        $propLoop = New-PropertyItem -id 0x5101 -type 3 -len 2 -val ([BitConverter]::GetBytes([UInt16]0))

        $images[0].SetPropertyItem($propDelay)
        $images[0].SetPropertyItem($propLoop)

        $params.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($encoder, [long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
        $images[0].Save($outputFile, $codec, $params)

        for($i = 1; $i -lt $images.Count; $i++){
            $params.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($encoder,[long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
            $images[0].SaveAdd($images[$i], $params)
        }
        $params.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new($encoder,[long][System.Drawing.Imaging.EncoderValue]::Flush)
        $images[0].SaveAdd($params)
        
        foreach($img in $images){$img.Dispose()}

        Remove-Item $tempFolder -Recurse -Force

        Write-Host "Saved to $outputFile"
    }
}

function Record-ScreenAVI{
    param(
        [string]$outputFile = $(Join-Path (Get-Location) ("Recording_{0}.avi" -f (Get-Date -Format "yyyyMMdd_HHmmss"))),
        [int]$durationMs = 0,
        [int]$intervalMs = 250,
        [switch]$fullScreen,
        [switch]$compress = $true,
        [uint32]$compressionLevel = 5000
    )

    if($compressionLevel -lt 0 -or $compressionLevel -gt 10000){
        Write-Host -ForegroundColor Red "Invalid compressionLevel, must be an integer between 0 and 10,000."
        return
    }
    $compressionLevel = (10000 - $compressionLevel) # The actual compression level is inverted internally

    $rect = Select-ScreenRect -fullScreen:$fullScreen
    if($rect.Width -le 0 -or $rect.Height -le 0){return}

    $X = $rect.X
    $Y = $rect.Y
    $Width = $rect.Width
    $Height = $rect.Height

    $frames = [math]::Floor($DurationMs / $IntervalMs)

    [AviNative]::AVIFileInit()

    $pfile = [IntPtr]::Zero
    [void][AviNative]::AVIFileOpen(
        [ref]$pfile,
        $outputFile,
        [AviNative]::OF_CREATE -bor [AviNative]::OF_WRITE,
        [IntPtr]::Zero
    )

    $streamInfo = [AviNative+AVISTREAMINFO]::new()
    $streamInfo.fccType = 0x73646976  # 'vids' backwards as bytes
    $streamInfo.dwScale = 1
    $streamInfo.dwRate = 1000 / $intervalMs
    $streamInfo.dwLength = $frames
    $streamInfo.dwSuggestedBufferSize = $Width * $Height * 3
    $streamInfo.rcFrame = [NativeAVI+RECT]@{left = $X; right = $Width; top = $Y; bottom = $Height}
    $streamInfo.szName = "ScreenCapture"

    $pStream = [IntPtr]::Zero
    $res = [AviNative]::AVIFileCreateStream($pfile, [ref]$pStream, [ref]$streamInfo)

    if($res -ne 0){
        throw "Failed to create the AVI stream. Err code: $res"
    }

    $compressed = $false
    if($compress){
        $opts = [NativeAVI+AVICOMPRESSOPTIONS]::new()
        $opts.fccType    = 0x73646976  # 'vids' backwards as bytes
        $opts.fccHandler = 0x6376736d  # 'msvc' backwards as bytes
        $opts.dwKeyFrameEvery = 30
        $opts.dwQuality = $compressionLevel

        $pCompressed = [IntPtr]::Zero
        $res = [NativeAVI]::AVIMakeCompressedStream(
            [ref]$pCompressed,
            $pStream,
            [ref]$opts,
            [IntPtr]::Zero
        )

        if($res -eq 0 -and $pCompressed -ne [IntPtr]::Zero){
            $compressed = $true
        }else{
            Write-Host -ForegroundColor Yellow "Compression was selected, but the MSVC codec was missing, the resulting AVI file will be uncompressed."
        }
    }

    $stride = (($Width * 3 + 3) -band 4)

    $bmpHeader = [AviNative+BITMAPINFOHEADER]::new()
    $bmpHeader.biSize = [Runtime.InteropServices.Marshal]::SizeOf($bmpHeader)
    $bmpHeader.biWidth = $Width
    $bmpHeader.biHeight = $Height
    $bmpHeader.biPlanes = 1
    $bmpHeader.biBitCount = 24
    $bmpHeader.biCompression = 0
    $bmpHeader.biSizeImage = $stride * $Height

    [void][AviNative]::AVIStreamSetFormat(
        $(if($compressed){$pCompressed}else{$pStream}),
        0,
        [ref]$bmpHeader,
        [Runtime.InteropServices.Marshal]::SizeOf($bmpHeader)
    )

    if($durationMs -eq 0){
        Write-Host "Recording indefinitely; Press Ctrl+C to stop."
    }else{
        Write-Host "Recording for $durationMs milliseconds..."
    }

    try{
        $bmp = [System.Drawing.Bitmap]::new($Width, $Height, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $g = [Drawing.Graphics]::FromImage($bmp)
        $captureRect = [System.Drawing.Rectangle]::new(0, 0, $Width, $Height)
        for($i = 0; $i -lt $frames; $i++){
            $g.CopyFromScreen($rect.Location, [Drawing.Point]::Empty, $rect.Size)

            $bmp.RotateFlip([Drawing.RotateFlipType]::RotateNoneFlipY) # it's bottom up for some reason

            $bmpData = $bmp.LockBits(
                $captureRect,
                [Drawing.Imaging.ImageLockMode]::ReadOnly,
                [Drawing.Imaging.PixelFormat]::Format24bppRgb
            )

            [void][AviNative]::AVIStreamWrite(
                $(if($compressed){$pCompressed}else{$pStream}),
                $i,
                1,
                $bmpData.Scan0,
                ($stride * $Height),
                [AviNative]::AVIIF_KEYFRAME,
                [IntPtr]::Zero,
                [IntPtr]::Zero
            )

            $bmp.UnlockBits($bmpData)
            
            [System.Threading.Thread]::Sleep($IntervalMs)
        }
        
        $g.Dispose()
        $bmp.Dispose()
    }catch{
        Write-Host -ForegroundColor Cyan $error[0]
    }finally{
        if($compressed){[void][AviNative]::AVIStreamRelease($pCompressed)}
        [void][AviNative]::AVIStreamRelease($pStream)
        [void][AviNative]::AVIFileRelease($pfile)
        [AviNative]::AVIFileExit()
    }

    Write-Host "AVI recording finished! Saved to $outputFile"
}
