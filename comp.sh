#!/bin/bash

DESKTOP="$HOME/Desktop"
WORKSPACE="$HOME/Programming/neotokyo-sourcemod-plugins/scripting"

if [[ "$1" -eq "17" ]]; then
	TARGETVER="1.7.3-git5334";
	SPVER="SPVER=17";
elif [[ "$1" -eq "19" ]]; then
	TARGETVER="1.9.0-git6282-windows";
	SPVER="SPVER=19";
elif [[ "$1" -eq "110" ]]; then
	TARGETVER="1.10.0-git6445-windows";
	SPVER="SPVER=110";
else
	echo "Asked wrong version";
fi

SMPATH=$DESKTOP/neotokyo/sourcemod-$TARGETVER

cd $WORKSPACE;
if [[ "$2" -eq "all" ]]; then
	for file in *.sp; do
		$SMPATH/scripting/spcomp ${SPVER} -o"$SMPATH/scripting/compiled/${file%.sp}.smx" "$WORKSPACE/${file}";
		echo "done with ${file}";
	done
else
		$SMPATH/scripting/spcomp ${SPVER} -o"$SMPATH/scripting/compiled/${2%.sp}.smx" "$WORKSPACE/${2}";
fi
