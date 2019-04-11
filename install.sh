#!/bin/sh

# Default is branch master for production
BRANCH="master"

# Dev-only -> if a branch is supplied in argument take it
if [ ! -z "$1" ]; then
    BRANCH="$1"
fi

run_it() {

    PREFIX="/usr/local"

    set -e
    set -u

    # Let's display everything on stderr.
    exec 1>&2

    UNAME=$(uname)
    # Check to see if it starts with MINGW.
    if [ "$UNAME" ">" "MINGW" -a "$UNAME" "<" "MINGX" ] ; then
        echo "Zenaton is not currently available on Windows, please contact the support: louis@zenaton.com"
        exit 1
    fi
    if [ "$UNAME" != "Linux" -a "$UNAME" != "Darwin" ] ; then
        echo "Sorry, this OS is not supported yet via this installer."
        echo "For more details on supported platforms, see https://www.zenaton.com/documentation"
        exit 1
    fi

    if [ "$UNAME" = "Darwin" ] ; then
        PLATFORM="macOSX"
    fi

    if [ "$UNAME" = "Linux" ] ; then

        # Find the type of linux distribution
        case $(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2) in
            "") LINUX_TYPE=$(grep -E '^ID=' /etc/os-release | cut -d= -f2) ;;
            *) LINUX_TYPE=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2) ;;
        esac

        if [ "$LINUX_TYPE" = "debian" ]; then
            # Debian kernel platform
            PLATFORM="debian"
        elif [ "$LINUX_TYPE" = "centos" -o "$LINUX_TYPE" = '"centos rhel fedora"' ]; then
            # Centos kernel platform
            PLATFORM="centos"
        else
            echo "Sorry, Zenaton is currently not available for $LINUX_TYPE. Please contact the support on zenaton.com"
            exit 1
        fi
    fi

    # trap "echo Installation failed." EXIT
    if [ -z $HOME ] || [ ! -d $HOME ]; then
        echo "The installation and use of Zenaton requires the \$HOME environment variable be set to a directory where its files can be installed."
        exit 1
    fi

    # if you already have zenaton installed, we do clean install here:
    if [ -e "$HOME/.zenaton" ]; then

        # Look if the zenaton worker process is running on the machine
        PROCESS_NUM=$(ps -ef | grep "worker_umbrella" | grep -v "grep" | wc -l)
        if [ $PROCESS_NUM -gt 1 ] ; then
            # means true - turn it off
            echo "Turning off your existing Zenaton agent."
            $HOME/.zenaton/bin/worker_umbrella stop
        fi
        # Remove the previous installation
        echo "Removing your existing Zenaton agent."
        rm -rf "$HOME/.zenaton"
    fi

    TARBALL_URL="https://raw.githubusercontent.com/zenaton/archive/${BRANCH}/${PLATFORM}/zenaton.tar.gz"
    INSTALL_TMPDIR="$HOME/.zenaton-install-tmp"
    TARBALL_FILE="$HOME/.zenaton-tarball-tmp"

    cleanUp() {
        rm -rf "$TARBALL_FILE"
        rm -rf "$INSTALL_TMPDIR"
    }

    # Remove temporary files now in case they exist.
    cleanUp

    # # Make sure cleanUp gets called if we exist abnormally
    trap cleanUp EXIT

    mkdir -p "$INSTALL_TMPDIR/.zenaton"

    # Only show progress bar animations if we have a tty
    # (Prevents tons of console junk when installing within a pipe)
    VERBOSITY="--silent";
    if [ -t 1 ]; then
        VERBOSITY="--progress-bar"
    fi

    echo "Downloading Zenaton agent."
    # keep trying to curl the file until it works (resuming where possible)
    MAX_ATTEMPTS=10
    RETRY_DELAY_SECS=5
    set +e
    ATTEMPTS=0
    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]
    do
        ATTEMPTS=$((ATTEMPTS + 1))

        curl $VERBOSITY --fail --continue-at - \
            "$TARBALL_URL" --output "$TARBALL_FILE"

        if [ $? -eq 0 ]
        then
          break
        fi
        echo "Retrying download in $RETRY_DELAY_SECS seconds..."
        sleep $RETRY_DELAY_SECS
    done
    set -e

    # bomb out if it didn't work, eg no net
    test -e "${TARBALL_FILE}"
    tar -xzf "$TARBALL_FILE" -C "$INSTALL_TMPDIR/.zenaton" -o

    test -x "${INSTALL_TMPDIR}/.zenaton/zenaton"
    mv "${INSTALL_TMPDIR}/.zenaton" "$HOME"

    # just double checking :)
    test -x "$HOME/.zenaton/zenaton"

    # The `trap cleanUp EXIT` line above won't actually fire after the exec
    # call below, so call cleanUp manually.
    cleanUp

    echo
    echo "Zenaton agent has been installed in your home directory (~/.zenaton)."

    LAUNCHER="$HOME/.zenaton/zenaton"

    if cp "$LAUNCHER" "$PREFIX/bin/zenaton" > /dev/null 2>&1; then
        echo "Writing a launcher script to $PREFIX/bin/zenaton for your convenience."
        cat <<"EOF"
See the docs at: zenaton.com/documentation

EOF
elif type sudo >/dev/null 2>&1; then
    echo "Writing a launcher script to $PREFIX/bin/zenaton for your convenience."
    echo "This may prompt for your password."

    # New macs (10.9+) don't ship with /usr/local, however it is still in
    # the default PATH. We still install there, we just need to create the
    # directory first.
    # XXX this means that we can run sudo too many times. we should never
    #     run it more than once if it fails the first time
    if [ ! -d "$PREFIX/bin" ] ; then
        sudo mkdir -m 755 "$PREFIX" || true
        sudo mkdir -m 755 "$PREFIX/bin" || true
    fi
    if sudo cp "$LAUNCHER" "$PREFIX/bin/zenaton"; then
    cat <<"EOF"
See the docs at: zenaton.com/documentation

EOF
    else
        cat <<EOF

        Couldn't write the launcher script. Please either:

        (1) Run the following as root:
            cp "$LAUNCHER" /usr/bin/zenaton
        (2) Add "\$HOME/.zenaton" to your path, or
        (3) Rerun this command to try again.

        Then to get started, take a look at 'zenaton --help' or see the docs at
        zenaton.com/documentation
EOF
    fi
else
    cat <<EOF

    Now you need to do one of the following:

    (1) Add "\$HOME/.zenaton" to your path, or
    (2) Run this command as root:
        cp "$LAUNCHER" /usr/bin/zenaton

        Then to get started, take a look at 'zenaton --help' or see the docs at
        zenaton.com/documentation
EOF
fi

# Start Zenaton Agent (default port: 4001)
if [ -z "${SKIP_START:-""}" ]; then
    zenaton start
fi

trap - EXIT
}

run_it "$BRANCH"
