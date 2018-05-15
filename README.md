# release.sh

__release.sh__ generates an addon zip file from a Git or SVN checkout.

__release.sh__ works by creating a new project directory, checking out external
repositories within the project directory, then copying files from the checkout
into the project directory.  The project directory is then zipped to create a
distributable addon zip file.

__release.sh__ can also upload your zip file to CurseForge, WoWInterface, and
GitHub (as a release), but requires [jq](https://stedolan.github.io/jq/). See
[Usage](#usage) for more info.

__release.sh__ reads __.pkgmeta__ and supports the following directives. See the
[CurseForge Knowledge Base page](https://authors.curseforge.com/knowledge-base/world-of-warcraft/527-preparing-the-packagemeta-file) for more info.

  - *externals* (Git and SVN) Caveats: An external's .pkgmeta is only parsed for ignore and will not have localization keywords replaced.
  - *ignore*
  - *license-output* (creates an *All Rights Reserved* license)
  - *manual-changelog*
  - *move-folders*
  - *package-as*
  - *enable-nolib-creation* (defaults to no) Unlike using the Curse packager,
    manually uploading nolib packages has no affect for client users that choose
    to download libraries separately.

You can also use a few directives for WoWInterface uploading.

  - *wowi-archive-previous* : `yes|no` (defaults to yes) Archive the previous release.
  - *wowi-create-changelog* : `yes|no` (defaults to yes) Generate a Git changelog using
  BBCode that will be set when uploading. A manual changelog will always be used if set
  in the .pkgmeta. If you have [pandoc](http://pandoc.org/) installed, manual changelogs
  in Markdown format will be converted to BBCode; otherwise, the manual changelog will be
  used as-is.

__release.sh__ supports the following repository substitution keywords when
copying the files from the checkout into the project directory. See the
[CurseForge Knowledge Base page](https://authors.curseforge.com/knowledge-base/world-of-warcraft/532-repository-keyword-substitutions) for more info.

  - *@alpha@*...*@end-alpha@*
  - *@debug@*...*@end-debug@*
  - *@do-not-package@*...*@end-do-not-package@*
  - *@[localization](https://authors.curseforge.com/knowledge-base/world-of-warcraft/531-localization-substitutions)(locale="locale", format="format", ...)@*
    - *escape-non-ascii*
    - *handle-unlocalized*
    - *handle-subnamespaces="concat"*
    - *key*
    - *namespace*
    - *same-key-is-true*
    - *table-name*
  - *@no-lib-strip@*...*@end-no-lib-strip@*
  - *@non-alpha@*...*@end-non-alpha@*
  - *@non-debug@*...*@end-non-debug@*
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

__release.sh__ reads the TOC file, if present, to determine the name of the
project.

__release.sh__ assumes that tags (Git annotated tags and SVN tags) are named for
the version numbers for the project.  It will identify if the HEAD is tagged and
use that as the current version number.  It will search back through parent
commits for the previous tag that is a release version number and generate a
changelog containing the commits since that previous release tag.

By default, __release.sh__ creates releases in the *.release* subdirectory of the
top-level directory of the checkout.

# Using release.sh

The recommended way to include __release.sh__ in a project is to:

1.  Create a *.release* subdirectory in your top-level checkout.
2.  Copy __release.sh__ into the *.release* directory.
3.  Ignore the *.release* subdirectory in __.gitignore__.
4.  Run __release.sh__.

# Usage

```
Usage: release.sh [-cdelLosuz] [-t topdir] [-r releasedir] [-p curse-id] [-w wowi-id] [-g game-version]
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
  -p curse-id      Set the project id used on CurseForge for localization and uploading.
  -w wowi-id       Set the addon id used on WoWInterface for uploading.
  -g game-version  Set the game version to use for CurseForge uploading.
```

The following environment variables are necessary for uploading:

  - `CF_API_KEY` - your [CurseForge API token](https://wow.curseforge.com/account/api-tokens), required for the CurseForge API to fetch localization and upload files.
  - `WOWI_API_TOKEN` - your [WoWInterface API token](https://www.wowinterface.com/downloads/filecpl.php?action=apitokens), required for uploading to WoWInterface.
  - `GITHUB_OAUTH` - a [GitHub personal access token](https://github.com/settings/tokens), required for uploading to Github.
