# ScreenRec
Record your screen natively in both GIF and AVI!

No libraries, nuget, or any other dependencies other than Windows.

Just dot source the ps1 file like so:
. <PATH TO FILE>/file.ps1

Then you have two functions you can call. Record-ScreenAVI and Record-ScreenGIF. If you do not specify -fullscreen, you will have a selection mode start which will allow you to select the region you want to record. The AVI function also supports compression and defaults to 5000 of 10000 where 10000 is almost illegible lol. The default interval is 250ms, this is dependent on the machine's CPU power and the size of the region being recorded, so lowering the interval won't help if you're running on a potato and you start a fullscreen record. There is no audio included, but you could use the ScreenDraw to write on the screen if needed or alternative;y you could type in large font in notepad, just remember to add the Trance - 009 song to it if you go that route.
