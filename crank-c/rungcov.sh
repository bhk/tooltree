#!/bin/bash
#
# Execute a test and collect GCOV data atomically.  The coverage data from
# different object files will be merged to form a single `ccov` database.
#
# GCOV data flow:
#
#   1. Run a program that was built with `--coverage`.
#
#   2. Run GCOV, specifying an *object* file.  This generates a .gcov file
#      for each covered *source* file.
#
# GCOV problems:
#
#  * GCOV must be run in the working directory that was used to run the
#    compiler, or else it will exit with an error after failing to find the
#    source files.  This would not be a problem except that GCOV writes
#    .gcov files into the current working directory.  In our case, this
#    pollutes the source directory.
#
#  * GCOV emits .gcov data for all covered source files. There is no
#    reasonable way to predict what it will emit, or to detect what
#    it emitted, except by looking for *.gcov in the current directory
#    after the GCOV run.
#
#  * When GCOV emits .gcov files, it may clobber .gcov files from a previous
#    run of GCOV (when a source file contributes code to two object files.)
#
#  * During program execution, GCOV data files (.gcda) are written into the
#    directory that contained the *object* files that were linked into the
#    program.  There is no way to override this, meaning:
#
#      - You can't cleanly distribute a coverage-instrumented executable.
#
#      - Different programs overwrite the same data files. GCOV takes care
#        to merge the data from independent runs, and may even merge
#        simultaneous runs without corrupting the data, but the results will
#        be unpredictable unless you control the set of programs that have
#        executed between when the data files were first created and when
#        GCOV is run.
#
#        In order to support incremental builds correctly, we capture the
#        coverage results for one test program at a time.
#
# rungcov sequence:
#
#   1. Delete the .gcda files for each object file.
#
#   2. Run the test program.
#
#   3. Initialize `outfile` to an empty coverage file.
#
#   4. For each object file:
#
#       a) Run GCOV to generate .gcov files for each covered source file.
#
#       b) Run CCOV to read *.gcov and merge the data with `outfile`.
#
#       c) Remove all .gcov files.
#
# This is all performed in a lock so that parallel builds will not clobber
# .gcda or .gcov files.
#
# Usage:
#
#   rungcov.sh [options] command arg...
#
# Options:
#    -o outfile     Coverage data will be written to this file.
#    -O object      An object file to process with gcov (many may be specified)
#    -L lockdir     Directory to create [default = "*GCOVLOCK*";  "" => no lock]
#    -c ccov_cmd    Command to invoke `ccov` [default = "ccov"]
#    -g gcov_cmd    Command to invoke `gcov` [default = "gcov"]
#    -m secs        Maximum time to wait for lock
#

declare verbose="$RUNGCOV_VERBOSE"

declare lockdir="*GCOVLOCK*"

# If you have a coverage test that takes more than 5 minutes to run, you are
# probably doing something wrong... and you'll need to use the -m option.
declare locktimeout=300


lock () {
  declare rep=0
  declare echoed=0
  if [[ -n ${lockdir} ]]
  then
      while ! mkdir "${lockdir}" 2> /dev/null ; do
        if (( ++rep == 30 ))
        then
            # Don't be noisy unless it's probably stuck
            printf '%s' "rungcov.sh: Locking ${lockdir}"
            echoed=1
        elif (( rep == locktimeout*10 ))
        then
            printf 'TIMEOUT! Breaking lock.\n'
            return
        elif (( echoed && rep%10 ))
        then
            printf .
        fi
        sleep 0.1 || sleep 1
    done
    if [[ -n ${echoed} ]]
    then
        printf '\n'
    fi
  fi
}

unlock () {
    [[ -n ${lockdir} ]] && rmdir "${lockdir}" 2> /dev/null
}


log () {
    [[ -n ${verbose} ]] && printf '%s\n' "rungcov.sh: $*" > /dev/stderr
}


onexit() {
    declare code=$?
    unlock
    rm -f *.gcov
    if [[ ${code} != 0 ]]
    then
        log "failure (error=${code})"
    else
        log success
    fi
    exit ${code}
}


main() {
    declare gcov=gcov
    declare ccov=ccov
    declare objects=()
    declare noisy=/dev/null

    while getopts "c:g:m:L:O:o:qv" OPT
    do
        case ${OPT} in
            o) outfile=${OPTARG}
                ;;
            O) objects+=( "${OPTARG}" )
                ;;
            L) lockdir=${OPTARG}
                ;;
            g) gcov=${OPTARG}
                ;;
            c) ccov=${OPTARG}
                ;;
            m) locktimeout=${OPTARG}
                ;;
            v) verbose=1
                ;;
        esac
    done
    shift $(( ${OPTIND} - 1))

    if [[ -n ${verbose} ]]
    then
       noisy=/dev/stderr
    fi

    if [[ -z ${outfile} ]]
    then
        printf '%s\n' "rungcov: no output file specified [-o outfile]"
        exit 1
    fi

    trap onexit EXIT
    trap exit SEGV

    lock

    # delete gcda files (if present)
    log "rm -f ${objects[@]/%.o/.gcda}"
    rm -f "${objects[@]/%.o/.gcda}"

    # run program
    log "running: ${*}"
    "${@}" || exit $?

    # initialize with a valid but empty coverage file
    printf '%s\n' '#csv' > "${outfile}"

    declare o
    declare odir
    declare ofile

    for o in "${objects[@]}" ; do

        # with the MacOS LLVM toolchain "gcov OBJECTFILE" works, but the
        # Linux GCC toolchain needs "gcov -o OBJECTFILE_DIR OBJECTFILE_NAME"
        [[ ${o} =~ / ]] && odir=${o%/*} || odir=.
        ofile=${o##/*}

        # gcov complains to stderr if object has no coverage data
        if [[ -f ${o%.*}.gcno ]]
        then
            log "running: ${gcov} -o ${odir} ${ofile}"
            "${gcov}" -o "${odir}" "${ofile}" > ${noisy} || exit 100

            if stat *.gcov 2>/dev/null 1>/dev/null
            then
                "${ccov}" *.gcov "${outfile}" -o "${outfile}" || exit 101
                rm -f *.gcov
            fi

        else
            log "no data for ${o}"
        fi
    done
}

main "${@}"
