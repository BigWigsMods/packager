__release.sh__ generates a zippable addon directory from a Git checkout.

__release.sh__ works by creating a new project directory, checking out external
repositories within the project directory, then copying files from the Git
checkout into the project directory.  The project directory is then zipped to
create a distributable addon zipfile.

__release.sh__ reads .pkgmeta and supports the following directives:

  - *externals* (Git and SVN)
  - *ignore*
  - *license-output* (for default "All Rights Reserved" license)
  - *manual-changelog*
  - *move-folders*
  - *package-as*

__release.sh__ supports the following repository substitution keywords when
copying the files from the Git checkout into the project directory.

  - *@alpha@*...*@end-alpha@*
  - *@debug@*...*@end-debug@*
  - *@localization(locale="locale", format="format", ...)@*
    - *escape-non-ascii*
    - *handle-subnamespaces*
    - *handle-unlocalized*
    - *namespace*
  - *@no-lib-strip@*...*@end-no-lib-strip@*
  - *@non-alpha@*...*@end-non-alpha@*
  - *@non-debug@*...*@end-non-debug@*
  - *@project-version@*

__release.sh__ reads the TOC file, if present, to determine the name of the
project.

__release.sh__ assumes that annotated tags are named for the version numbers for
the project.  It will identify if the HEAD is tagged and use that as the
current version number.  It will search back through parent commits for the
previous annotated tag that is a release version number and generate a
changelog containing the commits since that previous release tag.

__release.sh__ will create a default license file in the project directory with
the contents "All Rights Reserved" if a license file does not already exist.

By default, __release.sh__ creates releases in a *release* subdirectory of the
top-level directory of the Git checkout.
