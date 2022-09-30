<img src="plugin_logo.png" align="right" height="84" />

# godotsize [![License](https://img.shields.io/github/license/the-sink/godotsize)](https://github.com/the-sink/godotsize/blob/main/LICENSE) [![Issues](https://img.shields.io/github/issues/the-sink/godotsize)](https://github.com/the-sink/godotsize/issues) ![Godot 4](https://img.shields.io/badge/Godot-v4.0-%23478cbf)


godotsize is a simple utility that helps you identify which files in your project are taking up the most space. It checks the size of each file in your project folder (or imported file size, see below), and displays them in a list, with the ones taking up more space displayed on top. For example:

![](https://i.imgur.com/UIVUyf4.png)

To open the size map window, go to Project > Tools and click the "Show Size Map..." option.

![](https://i.imgur.com/h3P6jfO.png)



---

## Import Data Scanning

There is a setting in the Options menu that can turn on import data scanning:

![](https://i.imgur.com/7XQR9ZI.png)

This option will, as described, scan the *imported file data*, instead of the file itself as it is stored in the project. This can become extremely useful for identifying files that will end up being very large on export. For example, the default `icon.svg` that comes with all projects is (currently) only `3.42 KB` on its own:

![](https://i.imgur.com/9oEDl6L.png)

But, when the compression mode is changed from **Lossless** to **VRAM Uncompressed**, the file size all of a sudden jumps to `65.59 KB`!

![](https://i.imgur.com/GbSZXiD.png)

Obviously that isn't much, but for larger files this can have a significant impact. Being able to identify these files (and correct them if neccesary) can be helpful in reducing the size of your exported projects.