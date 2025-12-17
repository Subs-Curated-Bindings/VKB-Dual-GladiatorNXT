# Sub's Currated Bindings - Dual VKB NXT Premium

> [!CAUTION]
> THESE BINDINGS REQUIRE JOYSTICK GREMLIN!

> [!NOTE]
> These binds take me a really long time to make and keep updated. Here are a few ways you can ensure I can afford to spend the time to keep doing this. Ranging from most impactful to still awesome.
> - Join on [Twtich](https://subs.twitch.tv/subliminalstv) Even if you don't watch livestreams this is a great way until we meet our first goal of 100 (Current 20/100)
> - Join directly on [my store](https://store.subliminal.gg/supporters) - This is a great way if you dont have a twitch or amazon account. You can also tip when you download. The button is really small but its there in checkout.
> - FREE Ways to support!! Have Amazon Prime? You get one [free Twitch Prime Sub](https://subs.twitch.tv/subliminalstv) per month! Finally come by and hang out while I'm live. Not only will you catch me playing but I might be updaing these binds or keeping up on the latest SC news and info. I will be streaming to YouTube at the same in the near future.

## Navigation

- [Change Log](#change-log)
- [Install Videos](#instalation-video-guides)
- [Known Issues](#known-issues)
- [Features & Functions](#feartures-and-fucntions)
  - [Freelook](#free-look)
  - [NEW! Eye Tracker Targeting](#eye-tracker-targeting)
  - [Adding Audio Files](#adding-audio-files)
  - [Removing Or Muting Text To Speech](#removing-or-muting-text-to-speach)
- [Troubleshooting](#troubleshooting)
- [Binding Charts](#binding-charts)

## Change Log

- 12.16.25 - Added a bind for `Self Repair All`
- 12.16.25 - Swapped Targeting Hat with Power Mangement Hat (I need center push on a targeting hat to make it 100% intuative so you dont have to reffer to the chart)
- 12.16.25 - Changed the targeting hat to include subtargeting for 4.5 engineering combat. (Very important going forward in SC)
- 12.16.25 - Added Pinning to the targeting hat (Great for multi-crew... very important in SC going forward lol)
- 12.16.25 - Changed `Tobii Eyetracker Target` to `Eye Tracker Target` want to shed light on cheaper alternatives like [Beam Eye Tracker](https://beam.subliminal.gg) IMO EVERYONE should be using an EYE tracker. I you cant afford [Tobii Eyetracker 5](https://tobii.subliminal.gg) then beam works great for the low price.
- 12.16.25 - Moved MFD binds to `R-C1 Hat` to make room for more targeting stuff.
- 12.16.25 - Add the TTS beack... I thought it was causing issues but they didnt and people like having the audio confirmation. If you would like to remove it, mute it, adjust volumme. Jump to [Removing Or Muting Text To Speech](#removing-or-muting-text-to-speach)
- Added notes the the JG profile to help people navigate it.
- Added curves so so users with cleared action maps fies dont have to invert for ship axis. (FYI-Your inversion settings are saved in your `actionmaps.xml)

## Instalation Video Guides

At the time of making these video guides I had not yet distributed VKB NXT Binds. These guides have little to do with the joysticks themselves so these videos are just fine to demonstrate how to set them up regardless of what sticks you use.

### vJoy Install Video

<a href="http://www.youtube.com/watch?feature=player_embedded&v=ugjgKPf1-rk
" target="_blank"><img src="http://img.youtube.com/vi/ugjgKPf1-rk/maxresdefault.jpg" 
alt="vJoy Install Video" width="640" height="360" border="0" /></a>

> [!TIP]
> Check 3rd video for vJoy settings!

### HIDHide Install Video

<a href="http://www.youtube.com/watch?feature=player_embedded&v=PyL156AywYQ
" target="_blank"><img src="http://img.youtube.com/vi/PyL156AywYQ/maxresdefault.jpg" 
alt="HIDHide Install Video" width="640" height="360" border="0" /></a>

> [!WARNING]
> This video shows the many ways you can use HIDHide. Watch this to understand what it does and refer to the next video for the exact settings you need for when you are loading my binds and then.

### Joystick Gremlin

<a href="http://www.youtube.com/watch?feature=player_embedded&v=mc-ozIogrpI
" target="_blank"><img src="http://img.youtube.com/vi/mc-ozIogrpI/maxresdefault.jpg" 
alt="Loading Enhanced Binds Video" width="640" height="360" border="0" /></a>

> [!Important]
> Assumes you have vJoy, HIDHide, and JG installed and lets you know how to load everything.

## Known Issues

### MFD Binds

MFD Binds do not import properly into Star Citizen, this is a bug. 4.5 seems to have an issue with the `Stop Watch` binds not importing as well (but those binds are don't work ingame anymore lol). They also have to be cleared manually to remove them. So you will need to add them manually, but hopefully they should stick after that. You can find the binds in the advanced keybind settings under `Vehicles - Multi Function Displays (MFDs)`

| Star Citizen Keybind | Physical Button | Virtual Button
| --------- | --------- | ---------
| MFD - Cycle Page - Forwards (Short Press) | `[M] R-C1 Right` | `button52 (Input2)`
| MFD - Cycle Page - Backwards (Short Press) | `[M] R-C1 Left` |  `button54 (Input2)`
| MFD - Movement - Up (Long Press) | `[M] R-C1 Up` |  `button51 (Input2)`
| MFD - Movement - Down (Long Press) | `[M] R-C1 Down` |  `button53 (Input2)`
| MFD - Movement - Left (Long Press) | `[M] R-C1 Left` |  `button54 (Input2)`
| MFD - Movement - Right (Long Press) | `[M] R-C1 Right` |  `button52 (Input2)`
| MFD - Select - Left Cast (Short Press) | `[M][DT] R-C1 Left` |  `button54 (Input2)(DT)`
| MFD - Select - Right Cast (Short Press) | `[M][DT] R-C1 Right` |  `button51 (Input2)(DT)`
| MFD - Quick Action - Self Repair All | `R-A2` |  `button3 (Input2)`

> [!TIP]
> To make a bind [DT] or Double Tap you need to first map the bind to any button on the first stick (usually the left one), then add the double tap with y, then bind it to what you actually want.

- Please hurry up and contribute to the [issue council report](https://issue-council.robertsspaceindustries.com/projects/STAR-CITIZEN/issues/STARC-133477) so they can fix this by Nevuary 32nd, 2955

### NXT NON-Evo Base Encoders Switched

I recently learned if you have the non EVO version of the NXTs your encoders are swithced and done match the binding chart. So you will need to use them as is or rebind the mmanually. Verysimple process.

### Some Turret Binds dont work properly

I have noticed some turret binds dont work properly like gyro. Turret speed limiter and the general speed limiter do work but you need to turn speed limiter on in the IFCS MFD page first. This could also be ship depenedant so im keeping the binds in and hoping CIG gets around to fixing it.

## Feartures and Fucntions

### Free-look

To use freelook. Go into 3rd person (up on `L-A4 Hat`). Now press the `R-A1 Ministick` in, to change the mode to analog (Red Light should turn on). Now you are free to look around. Click and HOLD in on the `L-A4 Hat` to reset view.

### Eye Tracker Targeting

The main way I Target in Star Citizen is via an Eye Tracker. This adds to immersion and is a lot easier than using the native binds. Just look at the target, press a button and then they are locked. There are two eye trackers I recommend.

- Tobii Eye Tracker is next generation head and eye tracking. Unlock unique features that deepen your level of immersion in your favorite games including Star Citizen, Microsoft Flight Simulator, DCS, and more.

  - For more info and 5% off visit <https://tobii.subliminal.gg> "Purchases using the link and code `subliminal` at checkout support the curration of these binds."

- For a more budget friendly alternative check out Beam Eye Tracker. It is software only, and does require you to use your own webcam. It has some limitations like playing in a dark room or seeing through your glasses. But if you have a webcam and want to try eye tracking this is a MUST HAVE IMO. There is a free trail on steam. Or you can buy it directly from beam.

  - For more info visit <https://beam.subliminal.gg> "Purchases using the link and purchasing through Beam directly support the curration of these binds. Purchasing through steam does not."

## Text to Speach & Play Sounds

In a past update I removed the "play audio file" action from the JG profile and also the Text To Speach feature. I'm sorry but im adding the TTS back. It turns out there was no issue with the Text To Speech. And users enjoy having confirmation that the mode switched in JG.

If you would like to use the audio files I created instead of the TTS or if you would like to remove or "mute" the TTS, below are instructions on how to do that.

### Adding Audio Files

- In the upper right hand corner of JG, you can select which mode you would like to edit. In the `SCM Mode`, `Aux Mode`, and `NAV Mode`, the left joystick `Button 3` cycles modes. To add the audio files you will need to add an action for `Play Sound` to audibly confirm when JG changes Modes.

- To add the provided audio files, click `Button 3` then look towards the bottom of the action panel underneath the last action. Click the remap drop down and select `play sound`. Then click the `Add` button next to it. Clicking the pencil button will allow you to use windows explorer to tell JG where to find the audio files.

- There are multiple options for what audio files you can use and of course you could use your own. The audio files I provide are either voices from "Computer" aka/LCARS from Star Trek or HAL9000. And HAL9000 has two variations of dialogue.

- The Salvage and Mining audio files are for those who only mine OR salvage and want to hear a more personalized message. Auxillary is for those who mine and salvage. (This has no effect on the binds or game.)

- Simply load the .wave audio file for the corresponding mode. To know which one to use just read whatever I have in the Cycle Modes long press box inside JG.

- Remember to do this for `button 3` in `SCM Mode`, `Aux Mode`, and `NAV Mode` for the left stick only

> [!TIP]  
> You must save the JG profile after making changes to avoid having to repeat this every time JG or your PC restarts. It is a good practice to `Save As` and not overright my original JG file incase you may need to reload that working one in the future.

### Removing or Muting Text To Speach

There are many ways to remove or mute joystick gremlin.

- The most simple way is to simply mute or reduce the volume in inside of `Windows Volume Mixer`

- If you would like to remove the TTS following the same steps as seen in the [Adding Audio Files](#adding-audio-files) to locate the TTS action and remove it by clicking the `X` in the upper right hand corner of the TTS box.

- And of course you can reduce the audio in JG as well. Or remove or change the text in the TTS box. But make sure you head the warning below if you are going to do that.

> [!TIP]  
> You must save the JG profile after making changes to avoid having to repeat this every time JG or your PC restarts. It is a good practice to `Save As` and not overright my original JG file incase you may need to reload that working one in the future.

## Troubleshooting

Common Enhanced bind issues and their fixes can be found in the FAQ In Discord

- <https://discord.com/channels/303670222097874945/1297919077062279209>

Common Joystick/Star Citizen related issues and their fixes can be found here

- <https://discord.com/channels/303670222097874945/1154143410215731201>

> [!NOTE]  
> If you have an issue not found in either of the FAQs, please read and follow the simple instructions in the pinned post in the [Enhanced Bindings Support Forum](<https://discord.com/channels/303670222097874945/1006954369800998992>) before posting your question or concern.

## Binding Charts

### NO MORE ADOBE!!!

I have finally escaped Adobe's firm grasp and now moved the the free alternative Affinity. https://www.affinity.studio/get-affinity
Plus Affinty is now FREE!! Meaning anyone can open the .af files and edit them.

### PDF Files are back

- I figured out how to make searchable PDFs in affinity!

### Printer Friendly Binding Chart

- The chart labled `[Print]` has a white backgound to conserve ink for people who would like to print it.

- PRO TIP: If you have the paid version of adobe acrobat you can open the PNG file inside it and select the "Poster" option in the print settings and change the scale from %100 to 30% and it will spplit the chart into two pages with 1 stick on each page. For other programs just remember that scalled down to 30% its small enough to fit each stick on its own page.

## Miscelanious

> [!NOTE]
> My binds are now open source. I need contributers to assist with small updates when a patch drops. DM me on discord if you are interested. <https://github.com/SubliminalsTV/Subs-Curated-Bindings>
