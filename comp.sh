#!/bin/bash
# call with $0 [one|all] [version] [script.sp] [DEBUG lvl]
# or $0 all

#WORKSPACE="$HOME/Programming/neotokyo-sourcemod-plugins/scripting"
WORKSPACE="$(pwd)"
DEBUG=""
if [[ "$2" -eq "17" ]]; then
	TARGETVER="1.7.3-git5334";
elif [[ "$2" -eq "19" ]]; then
	TARGETVER="1.9.0-git6282-windows";
elif [[ "$2" -eq "110" ]]; then
	TARGETVER="1.10.0-git6445-windows";
else
	echo "Asked wrong version";
	exit;
fi

if [[ "$#" -eq 4 ]]; then
	DEBUG="DEBUG=${4}"
fi

# path to compiler
SMPATH=/home_data/NEOTOKYO/ADMIN_2019/sourcemod-$TARGETVER

cd $WORKSPACE;
if [[ "${1}" == "all" ]]; then
	for file in *.sp; do
		echo "$SMPATH/scripting/spcomp ${DEBUG} -o"$SMPATH/scripting/compiled/${file%.sp}.smx" "$WORKSPACE/${file}"";
		$SMPATH/scripting/spcomp ${DEBUG} -o"$SMPATH/scripting/compiled/${file%.sp}.smx" "$WORKSPACE/${file}";
		echo "done with ${file}";
	done
else
		echo "$SMPATH/scripting/spcomp ${DEBUG} -o"$SMPATH/scripting/compiled/${3%.sp}.smx" "$WORKSPACE/${3}"";
		$SMPATH/scripting/spcomp ${DEBUG} -o"$SMPATH/scripting/compiled/${3%.sp}.smx" "$WORKSPACE/${3}";
fi
