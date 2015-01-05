#!/bin/sh
#
# Generate a zippable addon directory from a Git checkout.
#
# Usage: release.sh [tag]
#

tag="$1"

# Path to root of Git checkout.
topdir=..
# Path to directory containing the generated addon.
releasedir=$topdir/tmp
# Colon-separated list of patterns of files to be ignored when copying files.
ignore=".*:tmp/*"
# Colon-separated list of patterns of files that need keyword replacement.
keyword="Ovale.lua:Ovale.toc"

project="Ovale Spell Priority"
project_slug="Ovale"
if [ -n "$tag" ]; then
	project="$project $tag"
	changelog="ChangeLog-${project_slug}-$tag.txt"
else
	project="$project (development version)"
	changelog="ChangeLog.txt"
fi
echo "Generating zippable addon directory for $project."

# Simple .pkgmeta processor.
while read line; do
	case ${line} in
	package-as:*)
		phase=${line%%:*}
		package=${line#*: }
		pkgdir=$releasedir/$package
		if [ -d $pkgdir ]; then
			echo "Removing previous package directory: $pkgdir"
			rm -fr $pkgdir
		fi
		mkdir -p $pkgdir
		;;
	externals:*)
		phase=${line%%:*}
		;;
	ignore:*)
		phase=${line%%:*}
		;;
	*git*|*svn*)
		if [ "$phase" = "externals" ]; then
			dir=${line%%:*}
			uri=${line#*: }
			mkdir -p $pkgdir/$dir
			case $uri in
			git:*)
				echo "Getting checkout for $uri"
				git clone $uri $pkgdir/$dir
				;;
			svn:*)
				echo "Getting checkout for $uri"
				svn checkout $uri $pkgdir/$dir
				;;
			esac
		fi
		;;
	*"- "*)
		if [ "$phase" = "ignore" ]; then
			pattern=${line#*- }
			if [ -d "../$pattern" ]; then
				pattern="$pattern/*"
			fi
			if [ -z "$ignore" ]; then
				ignore="$pattern"
			else
				ignore="$ignore:$pattern"
			fi
		fi
		;;
	esac
done < ../.pkgmeta
find $pkgdir -name .git -print -o -name .svn -print | xargs rm -fr

# Copy files from working directory into the package directory.
find $topdir -name .git -prune -o -name release -prune -o -print | while read file; do
	file=${file#$topdir/}
	if [ "$file" != "$topdir" -a -f "$topdir/$file" ]; then
		# Check if the file should be ignored.
		list="$ignore:"
		ignored=
		while [ -n "$list" ]; do
			pattern=${list%%:*}
			list=${list#*:}
			case $file in
			$pattern)
				ignored=true
				break
				;;
			esac
		done
		if [ -z "$ignored" ]; then
			dir=${file%/*}
			if [ "$dir" != "$file" ]; then
				mkdir -p $pkgdir/$dir
			fi
			# Check if the file matches a pattern for keyword replacement.
			list="$keyword:"
			replaced=
			while [ -n "$list" ]; do
				pattern=${list%%:*}
				list=${list#*:}
				case $file in
				$pattern)
					replaced=true
					break
					;;
				esac
			done
			if [ -n "$replaced" -a -n "$tag" ]; then
				echo "Replacing repository keywords: $file"
				sed "s/@project-version@/$tag/g" $topdir/$file > $pkgdir/$file
			else
				echo "Copying: $file"
				cp $topdir/$file $pkgdir/$dir
			fi
		fi
	fi
done

# Find the previous release tag.
rtag=`git describe HEAD~1 --abbrev=0`
while true; do
	case $rtag in
	[0-9].[0-9]) break ;;
	[0-9].[0-9].[0-9]) break ;;
	[0-9].[0-9].[0-9][0-9]) break ;;
	[0-9].[0-9].[0-9][0-9][0-9]) break ;;
	[0-9].[0-9][0-9]) break ;;
	[0-9].[0-9][0-9].[0-9]) break ;;
	[0-9].[0-9][0-9].[0-9][0-9]) break ;;
	[0-9].[0-9][0-9].[0-9][0-9][0-9]) break ;;
	esac
	rtag=`git describe $rtag~1 --abbrev=0`
done
echo "Previous release tag: $rtag"

# Create changelog of commits since the previous release tag.
echo "Generating changelog of commits since $rtag."
cat > $pkgdir/$changelog << EOF
$project

Changes from version $rtag:

EOF
git log $rtag..HEAD --pretty=format:"- %B" >> $pkgdir/$changelog