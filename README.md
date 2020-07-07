# release.sh

__release.sh__ generates an addon zip file from a Git, SVN, or Mercurial
checkout.

__release.sh__ works by creating a new project directory, checking out external
repositories within the project directory, then copying files from the checkout
into the project directory.  The project directory is then zipped to create a
distributable addon zip file.

__release.sh__ creates the new project directory in the *.release* subdirectory
of the top-level directory of the checkout.

__release.sh__ can also upload your zip file to CurseForge, WoWInterface, and
GitHub (as a release), but requires [jq](https://stedolan.github.io/jq/). See
[Usage](#usage) for more info.

__release.sh__ assumes that tags (Git annotated tags and SVN tags) are named for
the version numbers for the project.  It will identify if the HEAD is tagged and
use that as the current version number.  It will search back through parent
commits for the previous tag and generate a changelog containing the commits
since that tag.

__release.sh__ uses the TOC file to determine the package name for the project.
You can also set the CurseForge project id (`-p`) and the WoWInterface addon
id (`-w`) by adding the following to the TOC file:

    ## X-Curse-Project-ID: 1234
    ## X-WoWI-ID: 5678

Your CurseForge project id can be found on the addon page in the "About Project"
side box. Your WoWInterface addon id is in the url for the addon, eg, the "5678"
in <https://wowinterface.com/downloads/info5678-MyAddon>.

__release.sh__ reads __.pkgmeta__ and supports the following directives. See the
[wiki page](https://github.com/BigWigsMods/packager/wiki/Preparing-the-PackageMeta-File)
for more info.

- *externals* (Git, SVN, and Mercurial) Caveats: An external's .pkgmeta is only
  parsed for ignore and externals will not have localization keywords replaced.
- *ignore*
- *manual-changelog*
- *move-folders*
- *package-as*
- *enable-nolib-creation* (defaults to no) Unlike using the Curse packager,
  manually uploading nolib packages has no affect for client users that choose
  to download libraries separately.
- *tools-used*
- *required-dependencies*
- *optional-dependencies*
- *embedded-libraries* Note: All externals will be marked as embedded, overriding
  any manually set relations in the pkgmeta.

You can also use a few directives for WoWInterface uploading.

- *wowi-archive-previous* : `yes|no` (defaults to yes) Archive the previous
  release.
- *wowi-create-changelog* : `yes|no` (defaults to yes) Generate a Git changelog
  using BBCode that will be set when uploading. A manual changelog will always
  be used if set in the .pkgmeta. If you have [pandoc](http://pandoc.org/)
  installed, manual changelogs in Markdown format will be converted to BBCode;
  otherwise, the manual changelog will be used as-is.

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
- *@alpha@*...*@end-alpha@* / *@non-alpha@*...*@end-non-alpha@*
- *@debug@*...*@end-debug@* / *@non-debug@*...*@end-non-debug@*
- *@do-not-package@*...*@end-do-not-package@*
- *@no-lib-strip@*...*@end-no-lib-strip@*
- *@retail@*...*@end-retail@* / *@non-retail@*...*@end-non-retail@*
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

## Build type keywords

*alpha*, *debug*, *do-not-package*, *no-lib-strip*, and *retail* are build type
keywords and are used to conditionally run a block of code based on the build
type with the use of comments.

`@do-not-package@` and `@end-do-not-package@` are a bit special. Everything
between the tags, including the tags themselves, will be removed from the file.
This will cause the line numbers of subsequent lines to change, which can result
in bug report line numbers not matching the source code.  The typical usage is
at the end of Lua files surrounding debugging functions and other code that end
users should never see or execute.

### In Lua files

`--@keyword@` and `--@end-keyword@`  
turn into `--[===[@keyword` and `--@end-keyword]===]`.

`--[===[@non-keyword@` and `--@end-non-keyword@]===]`  
turn into `--@non-keyword@` and `--@end-non-keyword@`.

### In XML files

`<!--@keyword@-->` and `<!--@end-keyword@-->`  
turn into `<!--@keyword` and `@end-keyword@-->`.

`<!--@non-keyword@ and @end-non-keyword@-->`  
turn into `<!--@non-keyword@-->` and `<!--@end-non-keyword@-->`.

### In TOC files

The lines with `#@keyword@` and `#@end-keyword@` get removed, as well as every
line in-between.

The lines with `#@non-keyword@` and `#@end-non-keyword@` get removed, as well as
removing a '# ' at the beginning of each line in-between.

## Using release.sh

The recommended way to include __release.sh__ in a project is to:

1. Create a *.release* subdirectory in your top-level checkout.
2. Copy __release.sh__ into the *.release* directory.
3. Ignore the *.release* subdirectory in __.gitignore__.
4. Run __release.sh__.

## Using release.sh to build a Classic release

To make use of the `@retail@` and `@non-retail@` keywords, __release.sh__ needs
to know what version of World of Warcraft the package is targeting.  This is
automatically detected using the `## Interface:` line of the addon's TOC file.

If your addon supports both retail and classic in the same branch, you can use
keywords in your TOC file to include the appropriate `## Interface:` line in the
package.

    #@retail@
    ## Interface: 80300
    #@end-retail@
    #@non-retail@
    # ## Interface: 11305
    #@end-non-retail@

__release.sh__ will target retail by default.  You can change this by passing a
different game version as an argument.  To target classic this would be
`release.sh -g 1.13.5`.

## Usage

    Usage: release.sh [-cdelLosuz] [-t topdir] [-r releasedir] [-p curse-id] [-w wowi-id] [-g game-version] [-m pkgmeta.yml]
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
      -g game-version  Set the game version to use for CurseForge uploading.
      -m pkgmeta.yaml  Set the pkgmeta file to use.

The following environment variables are necessary for uploading:

- `CF_API_KEY` - a [CurseForge API token](https://wow.curseforge.com/account/api-tokens),
  required for the CurseForge API to fetch localization and upload files.
- `WOWI_API_TOKEN` - a [WoWInterface API token](https://www.wowinterface.com/downloads/filecpl.php?action=apitokens),
  required for uploading to WoWInterface.
- `GITHUB_OAUTH` - a [GitHub personal access token](https://github.com/settings/tokens),
  required for uploading to GitHub.

__release.sh__ will attempt to load environment variables from a `.env` file in
the topdir or current working directory.  You can also edit __release.sh__ and
enter the tokens near the top of the file.
