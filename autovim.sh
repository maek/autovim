#!/bin/bash

# Copyright (C) 2016-2017  maek (maek@paranoici.org)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# A faster way to open your files

# TODO
#
# - print stats when validating db
# - clean --> purge
# - why not unlimited size db?
# - we need a way to purge a specific entry (-d + PATTERN?)




#==============================================================================
# Setup
#==============================================================================

readonly DATABASE=$HOME/.local/share/autovim/autovim.txt
readonly DATABASE_SIZE=10000

ACTION=OPEN
VERBOSE=1




#==============================================================================
# Utilities
#==============================================================================

#------------------------------------------------------------------------------
# Abort the execution and print an error message
#
# @param   the message to print
#------------------------------------------------------------------------------
abort()
{
	if [[ $# -gt 0 ]]
	then
		(( VERBOSE )) && echo "${0##*/}: $*" >&2
	fi

	exit 1
}


#------------------------------------------------------------------------------
# Restore the output streams and check the execution of the last command
#
# @param   the status
# @param   the error message
#------------------------------------------------------------------------------
catch()
{
	local readonly ERROR=$1
	local readonly ERROR_MESSAGE=$2

	# Restore the output streams
	exec 1>&3 3>&-
	exec 2>&4 4>&-

	if (( ERROR ))
	then
		abort "$ERROR_MESSAGE"
	fi
}


#------------------------------------------------------------------------------
# Suppress all the output streams
#------------------------------------------------------------------------------
try()
{
	# Save the output streams
	exec 3>&1
	exec 4>&2

	# Suppress them
	exec &>/dev/null
}


#------------------------------------------------------------------------------
# Print usage information
#------------------------------------------------------------------------------
usage()
{
	echo "Usage: ${0##*/} [OPTIONS] <ARGS...>"
	echo "A faster way to open your files"
	echo
	echo "Options:"
	echo "  -a <FILE...>      Add entries to the database"
	echo "  -c                Clean the database"
	echo "  -h                Print this help"
	echo "  -q                Do not write anything to stdout"
	echo "  -s                Print MRU files"
	echo "  -t                Validate the database"
}




#==============================================================================
# Routines
#==============================================================================

#------------------------------------------------------------------------------
# Check if the database already exists otherwise create it
#------------------------------------------------------------------------------
use_database()
{
	local readonly DATABASE_PATH=$(dirname "$DATABASE")

	if [[ ! -f $DATABASE ]]
	then
		try
		mkdir -p "$DATABASE_PATH"
		catch $? "Couldn't create $DATABASE_PATH"

		try
		touch "$DATABASE"
		catch $? "Couldn't create $DATABASE"
	fi

	return 0
}


#------------------------------------------------------------------------------
# Delete the database
#------------------------------------------------------------------------------
drop_database()
{
	if [[ -f $DATABASE ]]
	then
		try
		rm -f "$DATABASE"
		catch $? "Couldn't remove $DATABASE"
	fi

	return 0
}


#------------------------------------------------------------------------------
# Add an entry to the database
#
# Add an entry at the top if it doesn't already exist, otherwise move it there.
#
# @param   the file/entry to add
#------------------------------------------------------------------------------
update_database()
{
	local readonly FILE=$(realpath "$1")

	# Add only existing files
	if [[ ! -f $FILE ]]
	then
		abort "File not found"
	fi

	# Check if the file is already in the database
	if fgrep -q "$FILE" "$DATABASE"
	then
		# Move the file at the top
		try
		mv "$DATABASE" "$DATABASE.bak"
		catch $? "Couldn't write to the database"

		try
		fgrep -v "$FILE" "$DATABASE.bak" > "$DATABASE.tmp"
		catch $? "Couldn't write to the database"

		try
		echo "$FILE" | cat - "$DATABASE.tmp" > "$DATABASE"
		catch $? "Couldn't write to the database"

		rm -f "$DATABASE.tmp"
	else
		# Add the file at the top
		try
		mv "$DATABASE" "$DATABASE.bak"
		catch $? "Couldn't write to the database"

		try
		echo "$FILE" | cat - "$DATABASE.bak" | head -n "$DATABASE_SIZE" > "$DATABASE"
		catch $? "Couldn't write to the database"
	fi

	return 0
}


#------------------------------------------------------------------------------
# Open the file with Vim
#
# Open the first file that matches all the patterns with Vim
#
# @param   the patterns
#------------------------------------------------------------------------------
read_database()
{
	local PATTERN=$1
	local MATCHES=()
	local OPTIONS=-e

	# Build the search pattern concatenating all the sub-patterns
	while [[ -n $2 ]]
	do
		PATTERN="$PATTERN.*$2"
		shift
	done

	# Smart case match
	[[ $PATTERN =~ [[:upper:]] ]] || OPTIONS=-i

	if [[ -n $PATTERN ]]
	then
		# Get all the matches
		IFS=$'\n' MATCHES=( $(egrep "$OPTIONS" "$PATTERN" "$DATABASE") )  # Isn't this risky!?
	else
		# Get the last opened files
		IFS=$'\n' MATCHES=( $(head -n9 "$DATABASE") )  # Isn't this risky!?
	fi

	case ${#MATCHES[@]} in
		0)
			abort "Couldn't find any match"
			;;
		1)
			echo "${MATCHES[0]}"

			# Add the first match to the database
			update_database "${MATCHES[0]}"

			# Open the first match with Vim
			vim "${MATCHES[0]}"
			;;
		*)
			local i=1
			for FILE in "${MATCHES[@]}"
			do
				[[ i -lt 10 ]] || break  # Print not more than 9 matches
				printf "[%d] %s\n" $(( i++ )) "$FILE"
			done

			echo

			local n=-1
			while :
			do
				case $n in
					q)
						exit 0
						;;
					[1-$(( i - 1 ))])
						break
						;;
					*)
						echo -n "Select a file to open (q to abort): "
						;;
				esac

				# Get the user choice
				read n
			done

			# Add the selected match to the database
			update_database "${MATCHES[(( n - 1 ))]}"

			# Open the selected match with Vim
			vim "${MATCHES[(( n - 1 ))]}"
			;;
	esac

	return 0
}


#------------------------------------------------------------------------------
# Print database stats
#------------------------------------------------------------------------------
print_database()
{
	local i=1

	# Get the first 9 entries of the database
	IFS=$'\n' ENTRIES=( $(head -n 9 "$DATABASE") )  # Isn't this risky!?
	for FILE in "${ENTRIES[@]}"
	do
		printf "[%d] %s\n" $(( i++ )) "$FILE"
	done

	if [[ $(sed -n '$=' "$DATABASE") -gt 9 ]]
	then
		echo "..."
	fi

	return 0
}


#------------------------------------------------------------------------------
# Validate the database
#------------------------------------------------------------------------------
validate_database()
{
	# Read in all the entries of the database
	IFS=$'\n' ENTRIES=( $(cat "$DATABASE") )  # Isn't this risky!?

	# Erase the database
	try
	> "$DATABASE"
	catch $? "Couldn't write to the database"

	# Write back only the entries that match an existent file
	for ENTRY in "${ENTRIES[@]}"
	do
		[[ -f $ENTRY ]] || continue

		try
		echo "$ENTRY" >> "$DATABASE"
		catch $? "Couldn't write to the database"
	done

	return 0
}




#==============================================================================
# Main
#==============================================================================

# Initialize the database
use_database

# Parse options
while getopts ':achqst' OPT
do
	case $OPT in
		a)
			ACTION=ADD
			;;
		c)
			ACTION=CLEAN
			;;
		h)
			usage
			exit 0
			;;
		q)
			VERBOSE=0
			;;
		s)
			ACTION=STATS
			;;
		t)
			ACTION=VALIDATE
			;;
		\?)
			abort "Invalid option '-$OPTARG'"
			;;
	esac
done

# Adjust arguments
shift $(( OPTIND - 1 ))

# Execute
if [[ $# -eq 0 ]]
then
	case $ACTION in
		CLEAN)
			drop_database
			;;
		VALIDATE)
			validate_database
			;;
		STATS)
			print_database
			;;
		*)
			read_database
			;;
	esac
else
	case $ACTION in
		ADD)
			for ARG
			do
				update_database "$ARG"
			done
			;;
		*)
			read_database "$@"
			;;
	esac
fi

exit 0
