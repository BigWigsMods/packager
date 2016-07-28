release.sh
==========

__release.sh__ generates an addon zipfile from a Git or SVN checkout.

__release.sh__ works by creating a new project directory, checking out external
repositories within the project directory, then copying files from the checkout
into the project directory.  The project directory is then zipped to create a
distributable addon zipfile.

__release.sh__ can also upload your zipfile to CurseForge, WoWInterface, and
GitHub (as a release), but requires [jq](https://stedolan.github.io/jq/).

__release.sh__ reads __.pkgmeta__ and supports the following directives. See the [CurseForge Knowledge base page](http://legacy.curseforge.com/wiki/projects/pkgmeta-file/) for more info.

  - *externals* (Git and SVN)
  - *ignore*
  - *license-output* (for default *All Rights Reserved* license)
  - *manual-changelog*
  - *move-folders*
  - *package-as*

__release.sh__ supports the following repository substitution keywords when
copying the files from the checkout into the project directory. See the [CurseForge Knowledge base page](http://legacy.curseforge.com/wiki/repositories/repository-keyword-substitutions/) for more info.

  - *@alpha@*...*@end-alpha@*
  - *@debug@*...*@end-debug@*
  - *@do-not-package@*...*@end-do-not-package@*
  - *@localization(locale="locale", format="format", ...)@*
    - *escape-non-ascii*
    - *handle-subnamespaces*
    - *handle-unlocalized*
    - *namespace*
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

__release.sh__ will create a default license file in the project directory with
the contents *All Rights Reserved* if a license file does not already exist.

By default, __release.sh__ creates releases in the *.release* subdirectory of the
top-level directory of the checkout.

Using release.sh
================

The recommended way to include __release.sh__ in a project is to:

1.  Create a *.release* subdirectory in your top-level checkout.
2.  Copy __release.sh__ into the *.release* directory.
3.  Ignore the *.release* subdirectory in __.pkgmeta__.
4.  Run __release.sh__.

Usage
=====
```
Usage: release.sh [-celzusod] [-p slug] [-w wowi-id] [-r releasedir] [-t topdir] [-g version]
  -c               Skip copying files into the package directory.
  -e               Skip checkout of external repositories.
  -l               Skip @localization@ keyword replacement.
  -z               Skip zipfile creation.
  -u               Use Unix line-endings.
  -s               Create a stripped-down ``nolib'' package.
  -o               Keep existing package directory, overwriting its contents.
  -p slug          Set the project slug used on WowAce or CurseForge.
  -d               Skip uploading to CurseForge.
  -w wowi-id       Set the addon id used on WoWInterface for uploading.
  -r releasedir    Set directory containing the package directory. Defaults to ``$topdir/.release''.
  -t topdir        Set top-level directory of checkout.
  -g version       Set the game version for uploading to CurseForge and WoWInterface.
```

The following environment variables are necessary for uploading:

  - `CF_API_KEY` - your [CurseForge API key](https://wow.curseforge.com/home/api-key/), required for uploading to CurseForge
  - `GITHUB_OAUTH` - a [GitHub OAuth token](https://github.com/settings/tokens), required for uploading to Github
  - `WOWI_USERNAME` - your WoWInterface username, required for uploading to WoWInterface
  - `WOWI_PASSWORD` - your WoWInterface password, required for uploading to WoWInterface
