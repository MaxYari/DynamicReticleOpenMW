![Dynamic Reticle](https://i.imgur.com/CBAElYb.png)

![](https://i.imgur.com/YYFfIlT.png)

<p><font color="#ffffff">If you are looking for hit markers which were previously a part of this mod: </font><b><font color="#00ffff" size="4">Hit markers, hit sounds and slow-mo were completely moved into <a href="https://www.nexusmods.com/morrowind/mods/60362?tab=description">The Combat Juice mod</a> (and were also improved and expanded)</font></b></p>

### Version 1.5

Default settings were changed to provide a better immersive experience by default, you will probably have to adjust your Dynamic Reticle settings, sorry.

New reticle variants by [rockbiter68](https://www.nexusmods.com/profile/rockbiter68)!

Also Oblivion-style reticular enemy health bar is still in this mod, its just disabled by default for more immersive experience as I myself currently prefer [Simple Enemy Health Bars](https://www.nexusmods.com/morrowind/mods/56297?tab=files) (Top Version)

<p>Was developed to be used in tandem with a <a href="https://www.nexusmods.com/morrowind/mods/55327">Dynamic Camera mod</a>, but will work without it.</font></p>

<p><a href="https://ko-fi.com/maxyari"><img src="images/morrowind_kofi_banner_left_half_bright124.gif" width="25.72%" align="top" alt="Support me on Ko-fi"></a><a href="https://ko-fi.com/maxyari"><img src="images/banner_right.png" width="73.88%" align="top" alt="Support me on Ko-fi"></a><br><a href="https://ko-fi.com/maxyari"><img src="images/banner_glow.png" width="99.6%" align="top" alt=""></a></p>

## ⊹ Installation

- Requires OpenMW 0.49 or newer.
- Install and enable [Max Yari's Script Services (MSS)](https://www.nexusmods.com/morrowind/mods/60256), it's a required dependency.
- Install this mod with a mod organiser: download the archive (or this repository as an archive) and drag and drop it into your mod organiser of choice (e.g [Mod Organizer 2](https://github.com/ModOrganizer2/modorganizer/releases) on Windows or [Nerevarine Organizer](https://github.com/grazelandsnomad/nerevarine_organizer/releases/tag/v0.70) on Linux). Or [read this tutorial](https://modding-openmw.com/tips/installing-mods/) on how to install mods using the launcher or completely manually (it's also very easy).
- Enable the mod's .omwscripts file in the "Content Files" tab of the OpenMW launcher.
- Disable vanilla crosshair in **Options->Prefs->Crosshair (at the bottom).**
- Ensure that shaders are enabled in game settings (enemy HP widget is a shader).

## ⊹ Configuration

Check **Options->Scripts->Dynamic Reticle** - the mod is very configurable. You can even drop new reticle images into a supported folder (it's specified also there in options) and be able to select between them in script options.

## ⊹ How To Remove Vanilla Enemy Health Bar

If you are using the oblivion-style reticular health bar bundled with hits mod - you might want to disable original yellow enemy hp bar - this is how:

1. Find `./OpenMW/resources/vfs/mygui/openmw_hud.layout` (inside your OpenMW folder, not your Morrowind folder!), if you are using a mod replacing/modifying vanilla hud, such as the beautiful [Centered HUD for OpenMW](https://www.nexusmods.com/morrowind/mods/53267?tab=posts&BH=1) - look for `/mygui/openmw_hud.layout` inside the mod folder instead (if you are using a mod manager to install it)
2. Open the file with a text editor
3. Find an element with a name EnemyHealth (`name="EnemyHealth"`)
4. In the "position" property of that element - 3rd number is this element's length - set it to 0 to hide the element

e.g you might find an element that looks like this

```xml
<Widget type="ProgressBar" skin="MW_EnergyBar_Yellow" position="0 131 80 12" align="Center Bottom" name="EnemyHealth">
    <Property key="Visible" value="false"/>
</Widget>
```

inside position = "..." change 80 to 0. Save the file. Play the game.

## ⊹ Credits

Thanks to [rockbiter68](https://www.nexusmods.com/profile/rockbiter68) for creating fancy versions of the reticles (available in mod settings)

Some reticle assets are taken from [WoW combat mode plugin](https://github.com/djsmithdev/combatmode) (thanks to **choirbug**) and [Fargoth Morrowind Icon](https://www.nexusmods.com/morrowind/mods/50404).\
Sounds introduced in 1.2 update are from **Ovani Sound**, picked by **Sikreci**.\
The sliders, color pickers and selects in the settings are from [Super Settings Renderers](https://www.nexusmods.com/morrowind/mods/59673) by [ownlyme](https://next.nexusmods.com/profile/ownlyme).
