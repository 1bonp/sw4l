#! /bin/bash
#
# Get patches for a given recipe
#

here=$(pwd)
cd $(dirname $0)
there=$(pwd)
cd "$here"

recipe=${1:-ncurses}
where=${2}

if [ ! -r $recipe.vars ]; then
	if [ ! -r $recipe.env ]; then
		if bitbake -e $recipe > $recipe.env; then
			true
		else
			echo "Can't run bitbake; probably the environment was not set..."
		fi
	fi
	$there/get_vars.sh $recipe
fi

. $recipe.vars

PN=${yocto_vars["PN"]}
PV=${yocto_vars["PV"]}
where=${where:-${PN}_${PV}}

if [ -d "$where" ]; then
	echo "Directory '$where' already exists; please remove it first..."
	exit 1
fi

SRC_DIR=${yocto_vars["S"]:-$PN-$PV}
FILES_EXTRAPATHS=${yocto_vars["FILESEXTRAPATH"]//:/ }
FILES_PATHS=${yocto_vars["FILESPATH"]//:/ }
files_paths=
for dir in $FILES_EXTRAPATHS $FILES_PATHS; do
	if [ "$dir" = "__default" ]; then
		continue
	fi
	if [ -d $dir ]; then
		files_paths="$files_dirs ${dir%/}"
	fi
done

alternatives=$(
	for dir in $files_dirs; do
		for subdir in $dir/*; do
			subdir=${subdir%/}
			if [[ " $files_dirs " =~ " $subdir " ]]; then
				continue
			fi
			if [ -d $subdir ]; then
				basename $subdir
			fi
		done
	done | sort | uniq
)

tmpdir=/tmp/fetch.$$
mkdir -p $tmpdir
pnum=10

source_dir=${yocto_vars["S"]}
[ -n "$source_dir" ] || source_dir=$PN-$PV

first=true
for src in ${yocto_vars["SRC_URI"]}; do
#	echo src="'$src'"
	params="${src#*;}"
	src=${src%%;*}

	# Clear all known parameters
	for param in \
		apply striplevel patchdir mindate maxdate minrev maxrev rev notrev \
		unpack destsuffix subdir localdir subpath name downloadfilename
	do
		eval $param=
	done
	if [ "$src" != "$params" ]; then
		params="${params//;/ }"
		for param in $params; do
			eval $param
		done
		subdir=${subdir#$source_dir} # Suppress source directory from subdir
	fi

	case $src in
		*.patch | *.diff) 
			;;
		file://*)
			;;
		*)
			continue
			;;
	esac
	unset alt_src
	declare -A alt_src
	case $src in
		file:///*)
			src=${src#file://}
			;;
		file://*)
			src=${src#file://}
			for dir in $files_paths; do
				if [ -r "$dir/$src" ]; then
					src="$dir/$src"
					break
				fi
			done
			for alt in $alternatives; do
				for dir in $files_paths; do
					if [ -r "$dir/$alt/$src" ]; then
						alt_src[$alt]="$dir/$alt/$src"
						break
					fi
				done
			done
			;;
		http://*.patch | http://*.diff | ftp://*.patch | ftp://*.diff)
			fname=${src##*/}
			wget $src -o $tmpdir/$fname
			src=$tmpdir/$fname
			;;

		*)
			if $first; then
				case $src in
					http://*.tar | http://*.tar.Z | http://*.tar.gz | http://*.tar.bz2 | http://*.tar.xz | \
					ftp://*.tar | ftp://*.tar.Z | ftp://*.tar.gz | ftp://*.tar.bz2 | ftp://*.tar.xz)
						srctype="remote archive"
						srcloc="$src"
						first=false
						continue
						;;
					file://*.tar | file://*.tar.Z | file://*.tar.gz | file://*.tar.bz2 | file://*.tar.xz)
						srctype="local archive"
						srcloc="$src"
						first=false
						continue
						;;
					svn://* | svn+ssh://* | cvs://* | git://* | ssh://*)
						srctype="remote repository"
						srcloc="$src"
						first=false
						continue
						;;
				esac
			fi
			echo "Don't know (yet) how to fetch '$src'" >&2
			;;
	esac
	if [ ! -r $src ]; then
		echo "Can't read '$src'" >&2
		exit 1;
	fi
#	echo src="'$src'"
	case $src in
		*.patch | *.diff) 
			pname=$(printf "p%04d-%s\n" $pnum $(basename $src))
			pnum=$((pnum + 10))
			if $apply; then
				pdir="$where/patches"
			else
				pdir="$where/disabled_patches"
			fi
			mkdir -p "$pdir"
			cp $src "$pdir/$pname"
			for alt in $alternatives; do
				if [ -n "${alt_src[$alt]}" ]; then
					mkdir -p "$pdir/$alt"
					cp "${alt_src[$alt]}" "$pdir/$alt/$pname"
				fi
			done 
			;;
# Here we must check if extract is allowed (see in params) and check if it has to be extracted
# in a specific (source) directory or if it *contains* the source directory... Moreover we should
# probably just re-build the archive in a suitable form for it to be extracted by the import build step
#		*.tar | *.tar.Z | *.tar.gz | *.tar.bz2 | *.tar.xz)
#			mkdir -p "$where/resources/$subdir"
#			tar xf $src -C "$where/resources/$subdir"
#			for alt in $alternatives; do
#				if [ -n "${alt_src[$alt]}" ]; then
#					mkdir -p "$where/alt_resources/$alt/$subdir"
#					tar xf - "${alt_src[$alt]}" -C "$where/alt_resources/$alt/$subdir"
#				fi
#			done 
#			;;
		*)
			mkdir -p "$where/resources/$subdir"
			cp $src "$where/resources/$subdir"
			for alt in $alternatives; do
				if [ -n "${alt_src[$alt]}" ]; then
					mkdir -p "$where/alt_resources/$alt/$subdir"
					cp "${alt_src[$alt]}" "$where/alt_resources/$alt/$subdir"
				fi
			done 
			;;
	esac
done

package_id=${PN}
[ -z "$PV" ] || package_id="${package_id}_$PV"
[ -z "$PR" ] || package_id="${package_id}-$PR"

cat << EOF > $where/ac6_package_manifest.xml
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<package id="$package_id"}>
  <name>$PN</name>
  <version>$PV</version>
  <revision>$PR</revision>
  <typeId>fr.ac6.platform.c.autotools</typeId>
  <srctype>$srctype</srctype>
  <srcloc>$srcloc</srcloc>
  <properties isNative="false" usePlatform="true">
    <property name="make_other_flags" owner="internal" type=""></property>
    <property name="dest_dir" owner="internal" type="">DESTDIR</property>
    <property name="configure_other_flags" owner="internal" type="replace"></property>
    <property name="sub_packages" owner="internal" type="replace">doc dev dbg locale base</property>
    <property name="make_install_other_flags" owner="internal" type=""></property>
  </properties>
  <dependencies>
EOF
for dep in ${yocto_vars["DEPENDS"]}; do
	if [[ " ${yocto_vars["BASEDEPENDS"]} " =~ " $dep " ]]; then continue; fi 
	case $dep in
		pkgconfig-native | virtual/*-poky-linux-* | virtual/libc | makedepend-native)
			continue
			;;
	esac
	echo "<dependency type="buildtime">$dep</dependency>" >> $where/ac6_package_manifest.xml
done
for dep in ${yocto_vars["RDEPENDS"]}; do
	echo "<dependency type="runtime">$dep</dependency>" >> $where/ac6_package_manifest.xml
done
for dep in ${yocto_vars["RRECOMMENDS"]}; do
	echo "<dependency type="recommended">$dep</dependency>" >> $where/ac6_package_manifest.xml
done
for dep in ${yocto_vars["RSUGGESTS"]}; do
	echo "<dependency type="suggested">$dep</dependency>" >> $where/ac6_package_manifest.xml
done
cat <<EOF >> $where/ac6_package_manifest.xml
  </dependencies>
</package>
EOF
if [ -d "$where" ]; then
	echo "Package definition, patches and resources for '$recipe' placed in '$where'"
fi 
