#!/bin/bash
# call with $0 [one|all] [version] [script.sp}
# or $0 all

#WORKSPACE="$HOME/Programming/neotokyo-sourcemod-plugins/scripting"
WORKSPACE="$(pwd)"

if [[ "$2" -eq "17" ]]; then
	TARGETVER="1.7.3-git5334";
	SPVER="SPVER=17";
elif [[ "$2" -eq "19" ]]; then
	TARGETVER="1.9.0-git6282-windows";
	SPVER="SPVER=19";
elif [[ "$2" -eq "110" ]]; then
	TARGETVER="1.10.0-git6445-windows";
	SPVER="SPVER=110";
else
	echo "Asked wrong version";
	exit;
fi

# path to compiler
SMPATH=/home_data/NEOTOKYO/ADMIN_2019/sourcemod-$TARGETVER

cd $WORKSPACE;
if [[ "${1}" == "all" ]]; then
	for file in *.sp; do
		$SMPATH/scripting/spcomp ${SPVER} -o"$SMPATH/scripting/compiled/${file%.sp}.smx" "$WORKSPACE/${file}";
		echo "done with ${file}";
	done
else
		$SMPATH/scripting/spcomp ${SPVER} -o"$SMPATH/scripting/compiled/${3%.sp}.smx" "$WORKSPACE/${3}";
fi
