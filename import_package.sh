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

if [ $recipe.env -nt $recipe.vars -o $there/get_vars.sh -nt $recipe.vars ]; then
	rm -f $recipe.vars
fi
if [ ! -r $recipe.vars ]; then
	if [ ! -r $recipe.env ]; then
		if bitbake -e $recipe > $recipe.env; then
			true
		else
			echo "Can't run bitbake; probably the environment was not set..."
		fi
	fi
	$there/get_vars.sh $recipe.env
fi

. $recipe.vars

PN=${yocto_vars["PN"]}
PV=${yocto_vars["PV"]}
where=${where:-.}
if [ $(basename $where) != ${PN}_${PV} ]; then
	where=$where/${PN}_${PV}
fi

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
#[ -z "$PR" ] || package_id="${package_id}-$PR"

package_type=fr.ac6.platform.c.makefile
if [[ " $yocto_classes " =~ " autotools " ]]; then
	package_type=fr.ac6.platform.c.autotools
	configure_flags="--host=$arch_compiler_prefix --prefix=/usr"
fi
mkdir -p $where
cat << EOF > $where/ac6_package_manifest.xml
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<package id="$package_id">
  <name>$PN</name>
  <version>$PV</version>
  <revision>$PR</revision>
  <typeId>$package_type</typeId>
  <srctype>$srctype</srctype>
  <srcloc>$srcloc</srcloc>
  <properties isNative="false" usePlatform="true">
    <property name="compiler_path" owner="internal" type="default"/>
    <property name="compiler_prefix" owner="internal" type="default"/>
    <property name="make_other_flags" owner="internal" type="replace"/>
    <property name="dest_dir" owner="internal" type="replace">DESTDIR</property>
    <property name="configure_other_flags" owner="internal" type="replace">$configure_flags</property>
    <property name="make_install_other_flags" owner="internal" type="replace"/>
EOF

# Generate package definitions as properties
echo '    <property name="splitted_packages" owner="internal" type="replace">'${yocto_vars[PACKAGES]}'</property>' >> $where/ac6_package_manifest.xml
subpkgs=
for package in ${yocto_vars[PACKAGES]}; do
	subpkg=${package#$PN}
	if [ -z "$subpkg" ]; then
		subpkg=base
	else
		subpkg=${subpkg#-}
	fi
	if [ "$subpkg" != "$package" ]; then
		if [[ " $subpkgs " =~ " $subpkg " ]]; then
			true # This sub-package definition was already known
		else
			subpkgs="$subpkgs $subpkg"
		fi
	fi
	subpkg=${subpkg//-/_}
	for spec in FILES SUMMARY DESCRIPTION SECTION HOMEPAGE LICENSE RDEPENDS RRECOMMENDS RSUGGESTS; do
		if [ -z "${yocto_vars[${spec}_$package]}" ]; then continue; fi
		if [ "$spec" = "FILES" ]; then
			property=pattern_$subpkg
		else
			property=${spec}_$subpkg
		fi
		set -o noglob # Just in case there is stars that may get expanded in the script...
		echo '    <property name="'$property'" owner="internal" type="replace">'${yocto_vars[${spec}_$package]}'</property>' >> $where/ac6_package_manifest.xml
		set +o noglob
	done
	for spec in pkg_preinst pkg_postinst pkg_prerm pkg_postrm; do
		if [ -z "${yocto_functions[${spec}_$package]}" ]; then continue; fi
		script=${spec#pkg_}
		script_name=$package/$script
		set -o noglob # Just in case there is stars that may get expanded in the script...
		echo "#! /bin/sh" 						> $where/package_scripts/$script_name
		echo "do_$script()" ${yocto_functions[${spec}_$package]}	>> $where/package_scripts/$script_name
		echo do_$script 						>> $where/package_scripts/$script_name
		echo '    <property name="'${script^^}_$subpkg'" owner="internal" type="replace">'$script_name'</property>' >> $where/ac6_package_manifest.xml		
		set +o noglob
	done
done
echo '    <property name="sub_packages" owner="internal" type="replace">'${subpkgs# }'</property>' >> $where/ac6_package_manifest.xml

# Generate dependencies
cat <<EOF >> $where/ac6_package_manifest.xml
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
	echo '    <dependency type="buildtime">'$dep'</dependency>' >> $where/ac6_package_manifest.xml
done
# These should be later expanded to sub-package dependencies, as specified above...
for dep in ${yocto_vars["RDEPENDS"]}; do
	echo '    <dependency type="runtime">'$dep'</dependency>' >> $where/ac6_package_manifest.xml
done
for dep in ${yocto_vars["RRECOMMENDS"]}; do
	echo '    <dependency type="recommended">'$dep'</dependency>' >> $where/ac6_package_manifest.xml
done
for dep in ${yocto_vars["RSUGGESTS"]}; do
	echo '    <dependency type="suggested">'$dep'</dependency>' >> $where/ac6_package_manifest.xml
done
cat <<EOF >> $where/ac6_package_manifest.xml
  </dependencies>
</package>
EOF

# Now generate the default build steps - Note the script picked may depend on the package type (makefile or autotools)
mkdir -p $where/buildsteps
cat << EOF > $where/buildsteps/ac6_package_buildsteps.xml
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<buildsteps>
  <task id="task.fetch.$package_id" type="internal">
    <name>Fetch</name>
    <description>Fetch the package source</description>
    <class>fr.ac6.platform.default.task.fetchTask</class>
    <script>fetch.sh</script>
  </task>
  <task id="task.import.$package_id" type="internal">
    <name>Import</name>
    <description>Import the package source into Eclipse project</description>
    <class>fr.ac6.platform.default.task.importTask</class>
  </task>
  <task id="task.copy-resources.$package_id" type="internal">
    <name>Copy Resources</name>
    <description>Copy the resources into the project directory</description>
    <class>fr.ac6.platform.default.task.resourcesTask</class>
  </task>
  <task id="task.apply-patches.$package_id" type="internal">
    <name>Apply Patches</name>
    <description>Patch the project sources</description>
    <class>fr.ac6.platform.default.task.patchTask</class>
  </task>
  <task id="task.configure.$package_id" type="internal">
    <name>Configure</name>
    <description>Configure the project</description>
    <class>fr.ac6.platform.default.task.configureTask</class>
    <script>configure.sh</script>
  </task>
  <task id="task.compile.$package_id" type="internal">
    <name>Compile</name>
    <description>Launch target make all</description>
    <class>fr.ac6.platform.makefile.task.makeTask</class>
    <script>make_all.sh</script>
  </task>
  <task id="task.install.$package_id" type="internal">
    <name>Install</name>
    <description>Launch make install</description>
    <class>fr.ac6.platform.makefile.task.makeInstallTask</class>
    <script>make_install.sh</script>
  </task>
  <task id="task.split.$package_id" type="internal">
    <name>Split</name>
    <description>Split the generated files into development, debug, docs subentity</description>
    <class>fr.ac6.platform.default.task.splitTask</class>
    <script>split.sh</script>
  </task>
  <task id="task.populate-sysroot.$package_id" type="internal">
    <name>Populate sysroot</name>
    <description>Populating the sysroot</description>
    <class>fr.ac6.platform.makefile.task.populateSysrootTask</class>
    <script>populate_sysroot.sh</script>
  </task>
  <task id="task.build.$package_id" type="internal">
    <name>Build</name>
    <description>Build the package source</description>
    <class>fr.ac6.platform.label.task.buildTask</class>
  </task>
  <task id="task.make-clean.$package_id" type="internal">
    <name>Make clean</name>
    <description>Launch target make clean</description>
    <class>fr.ac6.platform.makefile.task.makeCleanTask</class>
    <script>make_clean.sh</script>
  </task>
  <task id="task.clean.$package_id" type="internal">
    <name>Clean</name>
    <description>Clean the package</description>
    <class>fr.ac6.platform.label.task.cleanTask</class>
  </task>
  <edge source="task.import.$package_id" target="task.fetch.$package_id"/>
  <edge source="task.copy-resources.$package_id" target="task.import.$package_id"/>
  <edge source="task.apply-patches.$package_id" target="task.copy-resources.$package_id"/>
  <edge source="task.configure.$package_id" target="task.apply-patches.$package_id"/>
  <edge source="task.compile.$package_id" target="task.configure.$package_id"/>
  <edge source="task.install.$package_id" target="task.compile.$package_id"/>
  <edge source="task.split.$package_id" target="task.install.$package_id"/>
  <edge source="task.populate-sysroot.$package_id" target="task.split.$package_id"/>
  <edge source="task.build.$package_id" target="task.populate-sysroot.$package_id"/>
  <edge source="task.clean.$package_id" target="task.make-clean.$package_id"/>
</buildsteps>
EOF
if [ -d "$where" ]; then
	echo "Package definition, patches and resources for '$recipe' placed in '$where'"
fi 
