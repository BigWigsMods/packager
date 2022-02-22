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

## Building with GitHub Actions

For a full example workflow, please check out the [wiki page](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow).

### Example using [options](#Usage)

```yaml
- uses: BigWigsMods/packager@v2
  with:
    args: -p 1234 -w 5678 -a he54k6bL
```

### What's new with v2

Support for multiple TOC files and multiple versions required completely
reworking how the game version and game type was handled.  The multiple build
workflow that has become common for people that support multiple game types
should continue to work as before, but I felt like it would be good to bump
the version number so anyone explicitly using a v1 tag won't experience any
surprises.

So what does this mean for you?

1. You only need to build a file once!  Just create [multiple TOC files](https://wowpedia.fandom.com/wiki/TOC_format#Multiple_client_flavors),
   one for each supported game type, and game versions will be set from them on
   upload.  So if you've already been dabbling with multiple TOC files and/or
   multiple versions, you no longer need to manually set the versions via `-g`
   or on the CurseForge website.

   **Note:** CurseForge still requires that a fallback TOC file exists.  So if
   you support all three game types, you may as well leave the fallback TOC file
   as one of the game types instead of creating three game type specific ones.

2. If you are using multiple `## Interface-Type` lines in your TOC file, you can
   now use the `-S` command line option or add `enable-toc-creation: yes` to
   your `.pkgmeta` file to automatically generate game type specific TOC files
   based on your existing preprocessing logic.  The fallback TOC file will use
   the base interface value as it's version.

   ```toc
   ## Interface: 90200
   ## Interface-Classic: 11402
   ## Interface-BCC: 20503
   ```

   Splitting the above TOC file would end up with `MyAddon_Vanilla.toc`,
   `MyAddon_TBC.toc`, and `MyAddon.toc` (retail).

3. If you use build version keywords (e.g., `@version-retail@` ... `@end-version-retail@`)
   for controlling what code blocks execute based on the build version, you
   need to switch to plain old Lua control statements.  Fortunately, there are
   some [constants](https://wowpedia.fandom.com/wiki/WOW_PROJECT_ID) set by
   Blizzard you can use for this.  If you use these keywords in xml files, you
   will have to reorganize your includes in the appropriate TOC files.

## Customizing the build

__release.sh__ uses the TOC file to determine the package name for the project.
You can also set the CurseForge project id (`-p`), the WoWInterface addon
id (`-w`) or the Wago project id (`-a`) by adding the following to the TOC file:

```toc
## X-Curse-Project-ID: 1234
## X-WoWI-ID: 5678
## X-Wago-ID: he54k6bL
```

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
- *enable-toc-creation* (defaults to no) Create game type specific TOC files
  from your TOC file if you have multiple `## Interface-Type:` lines.
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
  installed; otherwise, the manual changelog will be used as-is.  If set to `no`
  when using a generated changelog, Markdown will be used instead of BBCode.
  **Note**: Markdown support is experimental and needs to be requested on a
  per-project basis.

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
- `retail`,`version-retail`,`version-classic`,`version-bcc`: based on game
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

1. It will show as the non-retail build type, so either `-classic` or `-bcc`.
2. It will not be shown if "-classic" or "-bcc" is in the project version.
3. If it is included in the file name (it is by default) and #2 does not apply,
   it will also be appended to the file label (i.e., the name shown on
   CurseForge).

## Building for multiple game versions

__release.sh__ automatically detects what game version(s) the addon supports.
You only need to run a build once and the file will be tagged with the
appropriate versions when uploaded.

### Multiple TOC files

You can create [multiple TOC files](https://wowpedia.fandom.com/wiki/TOC_format#Multiple_client_flavors),
one for each supported game type, and __release.sh__ will use them to set the
build's game version.

If you have already been dabbling with multiple TOC files and/or multiple
versions, you no longer need to manually set the versions via `-g` or on the
CurseForge website.

**Note:** CurseForge still requires that a fallback TOC file exists (the TOC
file with the same name as the addon directory). So if you support all three
game types, you may as well leave the fallback TOC file as one of the game types
instead of creating three game type specific ones.

### Single TOC file

If you are using multiple `## Interface-Type` lines in a single TOC file, you
can now use the `-S` command line option or add `enable-toc-creation: yes` to
your `.pkgmeta` file to automatically generate game type specific TOC files
based on your existing preprocessing logic.  The fallback TOC file will use
the base interface value as it's version.

```toc
## Interface: 90200
## Interface-Classic: 11402
## Interface-BCC: 20503
```

Splitting the above TOC file would end up with `MyAddon_Vanilla.toc`,
`MyAddon_TBC.toc`, and `MyAddon.toc` (retail).

If you use build version keywords (e.g., `@version-retail@` ... `@end-version-retail@`)
for controlling what code blocks execute based on the build version, you
need to switch to plain old Lua control statements.  Fortunately, there are
some [constants](https://wowpedia.fandom.com/wiki/WOW_PROJECT_ID) set by
Blizzard you can use for this.  If you use these keywords in xml files, you
will have to reorganize your includes in the appropriate TOC files.

### Single game version

As the game officially supports multiple game versions now, manually setting the
version should be considered deprecated and only be used if the game version is
not being detected correctly.

You can specify what version of the game you're targeting with the `-g` switch.
You can use a specific version (`release.sh -g 1.14.2`), a list (`release.sh -g "9.2.0,1.14.2"`)
or the game type (`release.sh -g classic`).  Using a game type will set the game
version based on the appropriate TOC `## Interface` value.

## Building locally

The recommended way to include __release.sh__ in a project is to:

1. Create a *.release* subdirectory in your top-level checkout.
2. Copy __release.sh__ into the *.release* directory.
3. Ignore the *.release* subdirectory in __.gitignore__.
4. Run __release.sh__.

## Usage

```text
Usage: release.sh [options]
  -c               Skip copying files into the package directory.
  -d               Skip uploading.
  -e               Skip checkout of external repositories.
  -l               Skip @localization@ keyword replacement.
  -L               Only do @localization@ keyword replacement (skip upload to CurseForge).
  -o               Keep existing package directory, overwriting its contents.
  -s               Create a stripped-down "nolib" package.
  -S               Create a package supporting multiple game types from a single TOC file.
  -u               Use Unix line-endings.
  -z               Skip zip file creation.
  -t topdir        Set top-level directory of checkout.
  -r releasedir    Set directory containing the package directory. Defaults to "$topdir/.release".
  -p curse-id      Set the project id used on CurseForge for localization and uploading. (Use 0 to unset the TOC value)
  -w wowi-id       Set the addon id used on WoWInterface for uploading. (Use 0 to unset the TOC value)
  -a wago-id       Set the project id used on Wago Addons for uploading. (Use 0 to unset the TOC value)
  -g game-version  Set the game version to use for uploading.
  -m pkgmeta.yaml  Set the pkgmeta file to use.
  -n "{template}"  Set the package zip file name and upload label. Use "-n help" for more info.
```

```text
Usage: release.sh -n "{template}"
  Set the package zip file name and upload file label. There are several string
  substitutions you can use to include version control and build type infomation in
  the file name and upload label.

  The default file name is "{package-name}-{project-version}{nolib}{classic}".
  The default upload label is "{project-version}{classic}{nolib}".

  To set both, seperate with a ":", i.e, "{file template}:{label template}".
  If either side of the ":" is blank, the default will be used. Not including a ":"
  will set the file name template, leaving upload label as default.

  Tokens: {package-name}{project-revision}{project-hash}{project-abbreviated-hash}
          {project-author}{project-date-iso}{project-date-integer}{project-timestamp}
          {project-version}{game-type}{release-type}

  Flags:  {alpha}{beta}{nolib}{classic}

  Tokens are always replaced with their value. Flags are shown prefixed with a dash
  depending on the build type.
```

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
- grep
- sed
- curl
- zip
- version control software as needed:
  - git >= 2.13.0
  - subversion >= 1.7.0
  - mercurial >= 3.9.0 (pre-3.9 will have issues with [secure connections](https://www.mercurial-scm.org/wiki/SecureConnections))
- [jq](https://stedolan.github.io/jq/download/) >= 1.5 (when uploading)
- [pandoc](https://pandoc.org/installing.html) >= 1.19.2 (optional)
