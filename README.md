# release.sh

__release.sh__ generates an addon zip file from a Git, SVN, or Mercurial
checkout.

__release.sh__ works by creating a new project directory (*.release* by
default), copying files from the checkout into the project directory, checking
out external repositories then copying their files into the project directory,
then moves subdirectories into the project root.  The project directory is then
zipped to create a distributable addon zip file which can also be uploaded to
CurseForge, WoWInterface, Wago, and GitHub (as a release).

__release.sh__ assumes that tags (Git annotated tags and SVN tags) are named for
the version numbers for the project.  It will identify if the HEAD is tagged and
use that as the current version number.  It will search back through parent
commits for the previous tag and generate a changelog containing the commits
since that tag.

## Customizing the build

__release.sh__ uses the TOC file to determine the package name for the project.
You can also set the CurseForge project id (`-p`), the WoWInterface addon
id (`-w`) or the Wago project id (`-a`) by adding the following to the TOC file:

    ## X-Curse-Project-ID: 1234
    ## X-WoWI-ID: 5678
    ## X-Wago-ID: he54k6bL

Your CurseForge project id can be found on the addon page in the "About Project"
side box.

Your WoWInterface addon id is in the url for the addon, eg, the "5678"
in <https://wowinterface.com/downloads/info5678-MyAddon>.

Your Wago project id can be found on the developer dashboard.

### The PackageMeta file

__release.sh__ can read a __.pkgmeta__ file and supports the following
directives. See the [wiki page](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File)
for more info.

- *externals* (Git, SVN, and Mercurial) Caveats: An external's .pkgmeta is only
  parsed for ignore and externals will not have localization keywords replaced.
- *ignore*
- *changelog-title*
- *manual-changelog*
- *move-folders*
- *package-as*
- *enable-nolib-creation* (defaults to no) Caveats: nolib packages will only be
  uploaded to GitHub and attached to a release. Unlike with the CurseForge
  packager, manually uploaded nolib packages will not be used by the client when
  users have enabled downloading libraries separately.
- *tools-used*
- *required-dependencies*
- *optional-dependencies*
- *embedded-libraries* Note: All fetched externals will be marked as embedded,
  overriding any manually set relations in the pkgmeta.

You can also use a few directives for WoWInterface uploading.

- *wowi-archive-previous* : `yes|no` (defaults to yes) Archive the previous
  release.
- *wowi-create-changelog* : `yes|no` (defaults to yes) Generate a changelog
  using BBCode that will be set when uploading. A manual changelog will always
  be used instead if set in the .pkgmeta.
- *wowi-convert-changelog* : `yes|no` (defaults to yes) Convert a manual
  changelog in Markdown format to BBCode if you have [pandoc](http://pandoc.org/)
  installed; otherwise, the manual changelog will be used as-is.

### String replacements

__release.sh__ supports the following repository substitution keywords when
copying the files from the checkout into the project directory. See the
[wiki page](https://github.com/BigWigsMods/packager/wiki/Repository-Keyword-Substitutions)
for more info.

- *@[localization](https://github.com/BigWigsMods/packager/wiki/Localization-Substitution)(locale="locale", format="format", ...)@*
  - *escape-non-ascii*
  - *handle-unlocalized*
  - *handle-subnamespaces="concat"*
  - *key*
  - *namespace*
  - *same-key-is-true*
  - *table-name*
- *@file-revision@*
- *@project-revision@*
- *@file-hash@*
- *@project-hash@*
- *@file-abbreviated-hash@*
- *@project-abbreviated-hash@*
- *@file-author@*
- *@project-author@*
- *@file-date-iso@*
- *@project-date-iso@*
- *@file-date-integer@*
- *@project-date-integer@*
- *@file-timestamp@*
- *@project-timestamp@*
- *@project-version@*

### Build type keywords

Specific keywords used in a comment at the start (`@keyword@`) and end
(`@end-keyword@`) of a block of code can be used to conditionally run that code
based on the build type.  If the build type does not match, the block of code
is comment out so line numbers do not change.

Supported keywords and when the code block will run:

- `alpha`: in untagged builds.
- `debug`: never.  Code will only run when using an unpackaged source.
- `do-not-package`: never.  Same as `debug` except removed from the packaged
  file.
- `no-lib-strip`: _(not supported in Lua files)_ in any build other than a
  *nolib* build.
- `retail`,`version-retail`,`version-classic`,`version-bc`: based on game
  version.

`do-not-package` is a bit special. Everything between the tags, including the
tags themselves, will always be removed from the packaged file. This will cause
the line numbers of subsequent lines to change, which can result in bug report
line numbers not matching the source code.  The typical usage is at the end of
Lua files surrounding debugging functions and other code that end users should
never see or execute.

All keywords except `do-not-package` can be prefixed with `non-` to inverse the
logic.  When doing this, the keywords should start and end a **block comment**
as shown below.

More examples are available on the [wiki page](https://github.com/BigWigsMods/packager/wiki/Repository-Keyword-Substitutions#debug-replacements).

#### In Lua files

`--@keyword@` and `--@end-keyword@`  
turn into `--[===[@keyword` and `--@end-keyword]===]`.

`--[===[@non-keyword@` and `--@end-non-keyword@]===]`  
turn into `--@non-keyword@` and `--@end-non-keyword@`.

#### In XML files

**Note:** XML doesn't allow nested comments so make sure not to nest keywords.
If you need to nest keywords, you can do so in the TOC instead.

`<!--@keyword@-->` and `<!--@end-keyword@-->`  
turn into `<!--@keyword` and `@end-keyword@-->`.

`<!--@non-keyword@` and `@end-non-keyword@-->`  
turn into `<!--@non-keyword@-->` and `<!--@end-non-keyword@-->`.

#### In TOC files

The lines with `#@keyword@` and `#@end-keyword@` get removed, as well as every
line in-between.

The lines with `#@non-keyword@` and `#@end-non-keyword@` get removed, as well as
removing a '# ' at the beginning of each line in-between.

### Changing the file name

__release.sh__ uses the file name template `"{package-name}-{project-version}{nolib}{classic}"`
for the addon zip file.  This can be changed with the `-n` switch (`release.sh
-n "{package-name}-{project-version}"`).

These tokens are always replaced with their value:

- `{package-name}`
- `{project-revision}`
- `{project-hash}`
- `{project-abbreviated-hash}`
- `{project-author}`
- `{project-date-iso}`
- `{project-date-integer}`
- `{project-timestamp}`
- `{project-version}`
- `{game-type}`
- `{release-type}`

These tokens are "flags" and are conditionally shown prefixed with a dash based
on the build type:

- `{alpha}`
- `{beta}`
- `{nolib}`
- `{classic}`

`{classic}` has some additional magic:

1. It will show as the non-retail build type, so either `-classic` or `-bc`.
2. It will not be shown if "classic" (case insensitive) is in the project
   version.
3. If it is included in the file name and #2 does not apply, it will also be
   appended to the file label (i.e., the name shown).

## Building for multiple game versions

__release.sh__ needs to know what version of World of Warcraft the package is
targeting.  This is normally automatically detected using the `## Interface:`
line of the addon's TOC file.

If your addon supports both retail and classic in the same branch, you can use
multiple `## Interface-Type:` lines in your TOC file.  Only one `## Interface:`
line will be included in the packaged TOC file based on the targeted game
version.

    ## Interface: 90005
    ## Interface-Retail: 90005
    ## Interface-Classic: 11306
    ## Interface-BC: 20501

You specify what version of the game you're targeting with the `-g` switch. You
can use a specific version (`release.sh -g 1.13.6`) or you can use the game type
(`release.sh -g classic`).  Using a game type will set the game version based on
the appropriate TOC `## Interface` value.

You can also set multiple specific versions as a comma delimited list using the
`-g` switch (`release.sh -g 1.13.6,2.5.1,9.0.5`).  This will still only build
one package, with the the last version listed used as the target version for
the build.

**Setting multiple versions is not recommended!** The addon will always be
marked "Out of date" in-game for versions that do not match the TOC interface
value for the last version set. So even if you don't need any special file
processing, it will always be best to run the packager multiple times so the TOC
interface value is correct for each game version.

## Building locally

The recommended way to include __release.sh__ in a project is to:

1. Create a *.release* subdirectory in your top-level checkout.
2. Copy __release.sh__ into the *.release* directory.
3. Ignore the *.release* subdirectory in __.gitignore__.
4. Run __release.sh__.

## Usage

    Usage: release.sh [-cdelLosuz] [-t topdir] [-r releasedir] [-p curse-id] [-w wowi-id] [-g game-version] [-m pkgmeta.yml] [-n filename]
      -c               Skip copying files into the package directory.
      -d               Skip uploading.
      -e               Skip checkout of external repositories.
      -l               Skip @localization@ keyword replacement.
      -L               Only do @localization@ keyword replacement (skip upload to CurseForge).
      -o               Keep existing package directory, overwriting its contents.
      -s               Create a stripped-down "nolib" package.
      -u               Use Unix line-endings.
      -z               Skip zip file creation.
      -t topdir        Set top-level directory of checkout.
      -r releasedir    Set directory containing the package directory. Defaults to "$topdir/.release".
      -p curse-id      Set the project id used on CurseForge for localization and uploading. (Use 0 to unset the TOC value)
      -w wowi-id       Set the addon id used on WoWInterface for uploading. (Use 0 to unset the TOC value)
      -a wago-id       Set the project id used on Wago Addons for uploading. (Use 0 to unset the TOC value)
      -g game-version  Set the game version to use for uploading.
      -m pkgmeta.yaml  Set the pkgmeta file to use.
      -n archive-name  Set the archive name template. Defaults to "{package-name}-{project-version}{nolib}{classic}".

### Uploading

__release.sh__ uses following environment variables for uploading:

- `CF_API_KEY` - a [CurseForge API token](https://wow.curseforge.com/account/api-tokens),
  required for the CurseForge API to fetch localization and upload files.
- `WOWI_API_TOKEN` - a [WoWInterface API token](https://www.wowinterface.com/downloads/filecpl.php?action=apitokens),
  required for uploading to WoWInterface.
- `WAGO_API_TOKEN` - a [Wago Addons API token](https://addons.wago.io/account/apikeys),
  required for uploading to Wago Addons.
- `GITHUB_OAUTH` - a [GitHub personal access token](https://github.com/settings/tokens),
  required for uploading to GitHub.

__release.sh__ will attempt to load environment variables from a `.env` file in
the topdir or current working directory.  You can also edit __release.sh__ and
enter the tokens near the top of the file.

### Dependencies

__release.sh__ is mostly POSIX-compatible, so it should run in any Unix-like
environment provided the following are available:

- bash >= 4.3
- awk
- sed
- curl
- zip
- version control software as needed:
  - git >= 2.13.0
  - subversion >= 1.7.0
  - mercurial >= 3.9.0 (pre-3.9 will have issues with [secure connections](https://www.mercurial-scm.org/wiki/SecureConnections))
- [jq](https://stedolan.github.io/jq/download/) >= 1.5 (when uploading)
- [pandoc](https://pandoc.org/installing.html) >= 1.19.2 (optional)
